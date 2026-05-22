# Implementing a FLAME Backend

This guide explains how to implement a custom `FLAME.Backend` for alternative compute providers.

## Architecture Overview

FLAME separates concerns between three main components:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            PARENT NODE                                      │
│  ┌─────────────┐      ┌─────────────┐      ┌─────────────────────────────┐  │
│  │ FLAME.Pool  │─────▶│FLAME.Runner │─────▶│   YourBackend (callbacks)   │  │
│  └─────────────┘      └─────────────┘      └─────────────────────────────┘  │
│         │                    │                          │                   │
│         │                    │                          │                   │
└─────────│────────────────────│──────────────────────────│───────────────────┘
          │                    │                          │
          │                    │    ┌─────────────────────┘
          │                    │    │  1. init/1 - prepare state
          │                    │    │  2. remote_boot/1 - provision runner
          │                    │    │  3. remote_spawn_monitor/2 - spawn work
          │                    │    │  4. system_shutdown/0 - terminate runner
          │                    │    │  5. handle_info/2 - optional messages
          │                    │    │
          │                    ▼    ▼
┌─────────│────────────────────────────────────────────────────────────────────┐
│         │              RUNNER NODE (provisioned by backend)                  │
│         │                                                                    │
│         │         ┌──────────────────┐         ┌─────────────────────┐       │
│         └────────▶│ FLAME.Terminator │────────▶│  Your Application   │       │
│                   └──────────────────┘         └─────────────────────┘       │
│                          │                                                   │
│                          │ connects back via {ref, {:remote_up, pid}}        │
│                          │ shuts down via system_shutdown/0                  │
└──────────────────────────│───────────────────────────────────────────────────┘
                           │
                           ▼
                    reads FLAME_PARENT
                    env var on boot
```

## Lifecycle Sequence

```
                 PARENT                                    RUNNER
                   │                                         │
    Pool starts    │                                         │
    Runner         │                                         │
         ─────────▶│                                         │
                   │                                         │
             ┌─────┴─────┐                                   │
             │  init/1   │ prepare state, encode FLAME_PARENT│
             └─────┬─────┘                                   │
                   │                                         │
             ┌─────┴──────────┐                              │
             │ remote_boot/1  │ provision compute ──────────▶│ boot app
             │                │                              │
             │                │                              │ FLAME.Terminator
             │                │                              │ reads FLAME_PARENT
             │                │◀──{ref, {:remote_up, pid}}───│ connects back
             │                │                              │
             └─────┬──────────┘                              │
                   │                                         │
      FLAME.call   │                                         │
         ─────────▶│                                         │
             ┌─────┴─────────────────┐                       │
             │ remote_spawn_monitor/2│──spawn + monitor─────▶│ execute func
             └─────┬─────────────────┘                       │
                   │◀────────────result──────────────────────│
                   │                                         │
     idle timeout  │                                         │
     or shutdown   │                                         │
         ─────────▶│                                         │
                   │───{ref, {:remote_shutdown, :idle}}──────│
                   │                                    ┌────┴────────────┐
                   │                                    │system_shutdown/0│
                   │                                    └────┬────────────┘
                   │                                         │ terminate
                   ▼                                         ▼
```

## Callback Reference

### `init(opts) :: {:ok, state} | {:error, reason}`

**Called when:** A new `FLAME.Runner` process starts.

**Purpose:** Initialize backend state for one runner instance.

**What to do:**
1. Merge application config with pool options
2. Validate required configuration (API tokens, regions, etc.)
3. Generate a unique runner identifier
4. Create a parent reference with `make_ref()`
5. Encode parent info using `FLAME.Parent.new/5` and `FLAME.Parent.encode/1`
6. Store the encoded parent for later use in `remote_boot/1`

**Key fields for `FLAME.Parent.new/5`:**
- `ref` - the reference you created with `make_ref()`
- `pid` - use `self()` (the Runner process)
- `backend` - your backend module (e.g., `__MODULE__`)
- `node_base` - a unique node basename for the runner
- `host_env` - env var name on runner that contains its hostname (or `nil`)

**Example from FlyBackend:**

```elixir
def init(opts) do
  # Merge config sources
  conf = Application.get_env(:flame, __MODULE__) || []
  state = Map.merge(defaults, Map.new(Keyword.merge(conf, opts)))

  # Validate required config
  for key <- [:token, :image, :host, :app] do
    unless Map.get(state, key), do: raise ArgumentError, "missing :#{key}"
  end

  # Generate unique runner name and parent reference
  state = %{state | runner_node_base: "#{state.app}-flame-#{rand_id(20)}"}
  parent_ref = make_ref()

  # Encode parent info for the runner to read
  encoded_parent =
    parent_ref
    |> FLAME.Parent.new(self(), __MODULE__, state.runner_node_base, "FLY_PRIVATE_IP")
    |> FLAME.Parent.encode()

  # Store encoded parent in environment that will be passed to runner
  new_env = Map.put(state.env, "FLAME_PARENT", encoded_parent)

  {:ok, %{state | env: new_env, parent_ref: parent_ref}}
end
```

**Example from LocalBackend:**

```elixir
def init(opts) do
  defaults = Application.get_env(:flame, __MODULE__) || []
  _terminator_sup = Keyword.fetch!(opts, :terminator_sup)

  {:ok, defaults |> Keyword.merge(opts) |> Enum.into(%{})}
end
```

---

### `remote_boot(state) :: {:ok, terminator_pid, new_state} | {:error, reason}`

**Called when:** The pool needs a new runner and calls `Runner.remote_boot/3`.

**Purpose:** Provision compute, start your app on it, and wait for connection.

**What to do:**
1. Provision the compute resource (API call, container start, etc.)
2. Ensure the `FLAME_PARENT` environment variable is set on the runner
3. Wait for the terminator to connect with `{ref, {:remote_up, terminator_pid}}`
4. Return the terminator pid and updated state

**Critical:** The runner application must start `FLAME.Terminator` in its supervision tree.
The terminator reads `FLAME_PARENT` from the environment and connects back automatically.

**Example from FlyBackend:**

```elixir
def remote_boot(%FlyBackend{parent_ref: parent_ref} = state) do
  # 1. Provision the machine via API
  resp = create_machine_api_call(state)

  case resp do
    %{"id" => id, "private_ip" => ip} ->
      new_state = %{state | runner_id: id, runner_private_ip: ip}

      # 2. Wait for terminator to connect back
      remote_terminator_pid =
        receive do
          {^parent_ref, {:remote_up, remote_terminator_pid}} ->
            remote_terminator_pid
        after
          state.boot_timeout ->
            Logger.error("failed to connect within timeout")
            exit(:timeout)
        end

      # 3. Return success with terminator pid
      new_state = %{new_state |
        remote_terminator_pid: remote_terminator_pid,
        runner_node_name: node(remote_terminator_pid)
      }

      {:ok, remote_terminator_pid, new_state}

    error ->
      {:error, error}
  end
end
```

**Example from LocalBackend:**

```elixir
def remote_boot(state) do
  # LocalBackend starts terminator directly in the same VM
  parent = FLAME.Parent.new(make_ref(), self(), __MODULE__, "nonode", nil)
  name = Module.concat(state.terminator_sup, to_string(System.unique_integer([:positive])))
  opts = [name: name, parent: parent, log: state.log]

  spec = Supervisor.child_spec({FLAME.Terminator, opts}, restart: :temporary)
  {:ok, _sup_pid} = DynamicSupervisor.start_child(state.terminator_sup, spec)

  case Process.whereis(name) do
    terminator_pid when is_pid(terminator_pid) -> {:ok, terminator_pid, state}
  end
end
```

---

### `remote_spawn_monitor(state, func) :: {:ok, {pid, ref}} | {:error, reason}`

**Called when:** `FLAME.call/3`, `FLAME.cast/3`, or internal runner operations execute work.

**Purpose:** Spawn a function on the runner and monitor it.

**What to do:**
1. Accept either a zero-arity function or `{module, function, args}` tuple
2. Spawn the function in the runner's environment
3. Monitor the spawned process
4. Return `{:ok, {pid, monitor_ref}}`

For distributed backends, use `Node.spawn_monitor/2` or `Node.spawn_monitor/4`.
For local backends, use `spawn_monitor/1` or `spawn_monitor/3`.

**Example from FlyBackend:**

```elixir
def remote_spawn_monitor(%FlyBackend{} = state, term) do
  case term do
    func when is_function(func, 0) ->
      {pid, ref} = Node.spawn_monitor(state.runner_node_name, func)
      {:ok, {pid, ref}}

    {mod, fun, args} when is_atom(mod) and is_atom(fun) and is_list(args) ->
      {pid, ref} = Node.spawn_monitor(state.runner_node_name, mod, fun, args)
      {:ok, {pid, ref}}

    other ->
      raise ArgumentError, "expected function or MFA tuple, got: #{inspect(other)}"
  end
end
```

**Example from LocalBackend:**

```elixir
def remote_spawn_monitor(_state, term) do
  case term do
    func when is_function(func, 0) ->
      {pid, ref} = spawn_monitor(func)
      {:ok, {pid, ref}}

    {mod, fun, args} when is_atom(mod) and is_atom(fun) and is_list(args) ->
      {pid, ref} = spawn_monitor(mod, fun, args)
      {:ok, {pid, ref}}
  end
end
```

---

### `system_shutdown() :: term()`

**Called when:** The terminator needs to stop the runner system.

**Called from:** Inside the runner node by `FLAME.Terminator` when:
- Parent requests shutdown
- Parent node goes down
- Runner idles out (based on `idle_shutdown_after`)
- Failsafe timeout expires

**Purpose:** Terminate the runner's host system.

**What to do:**
- For real compute backends: call `System.stop()` to terminate the VM
- For local/test backends: return `:noop` (do nothing)

**Example from FlyBackend:**

```elixir
def system_shutdown do
  System.stop()
end
```

**Example from LocalBackend:**

```elixir
def system_shutdown, do: :noop
```

---

### `handle_info(msg, state) :: {:noreply, new_state}` (optional)

**Called when:** The Runner GenServer receives messages not handled internally.

**Purpose:** Handle backend-specific messages (provider webhooks, monitors, etc.).

**What to do:**
- Process any backend-specific messages
- Return `{:noreply, new_state}` with updated state

This callback is optional. If not implemented, unhandled messages are ignored.

---

## Messages from Terminator

The `FLAME.Terminator` on the runner sends these messages to the parent:

### `{ref, {:remote_up, terminator_pid}}`

Sent when the terminator successfully connects to the parent node.
Your `remote_boot/1` should wait for this message.

### `{ref, {:remote_shutdown, :idle}}`

Sent when the runner is shutting down due to idle timeout.
The Runner handles this internally; no backend action needed.

---

## Checklist for New Backends

1. **Module setup:**
   - [ ] Add `@behaviour FLAME.Backend`
   - [ ] Implement all required callbacks

2. **init/1:**
   - [ ] Merge application config with opts
   - [ ] Validate required configuration
   - [ ] Generate unique runner identifier
   - [ ] Create and encode `FLAME.Parent` struct
   - [ ] Store `FLAME_PARENT` for runner environment

3. **remote_boot/1:**
   - [ ] Provision compute resource
   - [ ] Pass `FLAME_PARENT` env var to runner
   - [ ] Wait for `{ref, {:remote_up, pid}}` message
   - [ ] Handle boot timeout
   - [ ] Return `{:ok, terminator_pid, new_state}`

4. **remote_spawn_monitor/2:**
   - [ ] Handle zero-arity functions
   - [ ] Handle `{mod, fun, args}` tuples
   - [ ] Spawn on runner (remote or local)
   - [ ] Return `{:ok, {pid, monitor_ref}}`

5. **system_shutdown/0:**
   - [ ] Terminate the runner system (or no-op for local)

6. **Runner application:**
   - [ ] Ensure `FLAME.Terminator` starts in supervision tree
   - [ ] Terminator reads `FLAME_PARENT` automatically via `FLAME.Parent.get/0`

---

## Reference Implementations

- `FLAME.FlyBackend` - Full distributed backend for Fly.io machines
- `FLAME.LocalBackend` - Simple local backend for development/testing
