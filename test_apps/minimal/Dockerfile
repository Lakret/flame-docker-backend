# Build from repo root: docker build -t minimal -f test_apps/minimal/Dockerfile .
#
# Layer order follows https://hexdocs.pm/mix/Mix.Tasks.Release.html#module-docker
# so dependency and compile layers stay cached across app changes.
ARG ELIXIR_VERSION=1.18.4
ARG OTP_VERSION=27.3.4
ARG ALPINE_VERSION=3.21.3

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-alpine-${ALPINE_VERSION}"
ARG RUNNER_IMAGE="alpine:${ALPINE_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

RUN apk add --no-cache build-base git

ENV MIX_ENV=prod

RUN mix local.hex --force && mix local.rebar --force

# Path dependency (flame_docker_backend)
WORKDIR /build
COPY mix.exs mix.lock ./
COPY lib lib

WORKDIR /build/test_apps/minimal
COPY test_apps/minimal/mix.exs test_apps/minimal/mix.lock* ./

RUN mix deps.get --only prod

# Compile-time config only; runtime.exs is copied after compile.
COPY test_apps/minimal/config/config.exs config/

RUN mix deps.compile

COPY test_apps/minimal/lib lib

RUN mix compile

# Changes to runtime.exs do not require recompiling dependencies.
COPY test_apps/minimal/config/runtime.exs config/

RUN mix release

FROM ${RUNNER_IMAGE}

RUN apk add --no-cache libstdc++ ncurses-libs

WORKDIR /app

ENV MIX_ENV=prod

COPY --from=builder /build/test_apps/minimal/_build/prod/rel/minimal ./

CMD ["bin/minimal", "start"]
