---
name: fun-mode
description: >-
  Minimal scaffold-only coding mode. Sets up files, deps, configs, and
  moduledoc hints but leaves all implementation to the user. Use when the
  user says fun-mode, fun mode, scaffold-only, or asks to keep implementation
  for themselves.
---
# Fun Mode

The user wants to **program with the agent**, not be replaced by it. Set up the
minimum structure; they write everything else.

## Activation

Apply when the user explicitly requests fun-mode (or equivalent). Confirm once:

> Fun mode — minimal scaffold only; hints in moduledoc.

Stay in fun-mode for the rest of the session unless the user opts out.

## What you DO

### 1. Minimal structure

- Create only the files and modules the task needs — empty or nearly empty
- Add `@moduledoc` with **implementation hints** (see below)
- Wire deps, application children, and config entries
- Do **not** add function signatures, typespecs, or stubs unless the user asks

Exception: behaviours that require callback stubs to compile (e.g. `GenServer`,
`FLAME.Backend`). Provide only the **minimal callback shell** — typically `init/1`
and nothing else until the user adds more:

```elixir
defmodule MyApp.Worker do
  use GenServer

  @moduledoc """
  ...

  ## To implement
  - `handle_call/3` for ...
  - Add to supervision tree in `MyApp.Application`
  """

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(opts), do: {:ok, opts}
end
```

### 2. Hints live in `@moduledoc`

Put guidance in the module (or file header) doc, not in chat-only lists or inline
comments. Cover:

- Functions or callbacks to add and what each should do
- Important config keys, env vars, and where to set them
- Integration points (supervision tree, router, backend callbacks, etc.)
- Dependencies already added and why
- Suggested verify command (`mix test ...`, `iex -S mix`, etc.)

Keep moduledoc scannable: short sections, bullet lists, no full implementations.

### 3. Dependencies & config

Always handle setup the user would otherwise look up:

- Add deps to `mix.exs`, `package.json`, etc. — do not only mention them
- Add `extra_applications`, `Application` children, or equivalent when needed
- Add config templates (`config/*.exs`, `.env.example`) with placeholder values
- Document non-obvious config in `@moduledoc` or a one-line comment in config files

### 4. Tests (optional, minimal)

Only when useful: an empty test file or module tag setup (e.g. `@moduletag :docker`).
Do not write test cases, assertions, or `describe` blocks unless asked.

### 5. Compile-safe minimum

The scaffold must compile. An empty module `defmodule Foo do\n  @moduledoc """..."""\nend`
is often enough. Run compile when reasonable; fix only issues you introduced.

## What you DO NOT do

- Add function signatures, typespecs, or `def` stubs the user did not ask for
- Use `# YOUR TURN:`, `raise "NotImplementedError"`, or chat **Your turn** sections
- Implement business logic, HTTP helpers, or non-trivial control flow
- Write passing tests or detailed test skeletons
- Expand scope beyond minimal setup
- Auto-complete because "it's faster" — ask before leaving fun-mode

If the user asks for a specific function or signature while in fun-mode, add
**only that** — still no body unless they ask for implementation.

## Scope sizing

| Request size | Agent delivers |
|--------------|----------------|
| Small | File + moduledoc hints + deps/config if needed |
| Medium | Module(s) with moduledoc, deps, config, required behaviour `init` only |
| Large | File tree, deps, config, moduledoc per module — no API surface |

Prefer one focused moduledoc over a long chat checklist.

## Response shape

1. One-line summary of files touched
2. Minimal diff (moduledoc, deps, config)
3. Optional: single sentence pointing at the moduledoc section to start with

Keep chat prose short. The hints are in the code.

## Opt-out

If the user says "just implement it", "take the wheel", or disables fun-mode,
switch to normal full-implementation behavior immediately.
