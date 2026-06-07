# Build from repo root: docker build -t minimal -f test_apps/minimal/Dockerfile .
ARG ELIXIR_VERSION=1.18.4
ARG OTP_VERSION=27.3.4
ARG ALPINE_VERSION=3.21.3

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-alpine-${ALPINE_VERSION}"
ARG RUNNER_IMAGE="alpine:${ALPINE_VERSION}"

# ============ Build Stage ============
FROM ${BUILDER_IMAGE} AS builder

RUN apk add --no-cache build-base git

WORKDIR /build

ENV MIX_ENV=prod

RUN mix local.hex --force && mix local.rebar --force

# Copy flame_docker_backend (the path dependency)
COPY mix.exs mix.lock ./
COPY lib lib

# Copy the minimal test app
COPY test_apps/minimal/mix.exs test_apps/minimal/mix.lock* test_apps/minimal/
COPY test_apps/minimal/config test_apps/minimal/config
COPY test_apps/minimal/lib test_apps/minimal/lib

WORKDIR /build/test_apps/minimal

RUN mix deps.get --only prod
RUN mix deps.compile

RUN mix release

# ============ Runner Stage ============
FROM ${RUNNER_IMAGE}

RUN apk add --no-cache libstdc++ ncurses-libs

WORKDIR /app

ENV MIX_ENV=prod

COPY --from=builder /build/test_apps/minimal/_build/prod/rel/minimal ./

CMD ["bin/minimal", "start"]
