# Build from repo root: docker build -t phx_minimal:latest -f test_apps/phx_minimal/Dockerfile .
#
# Layer order follows https://phoenix.hexdocs.pm/releases.html#containers so
# dependency, asset-tool, and compile layers stay cached across app changes.
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

WORKDIR /build/test_apps/phx_minimal
COPY test_apps/phx_minimal/mix.exs test_apps/phx_minimal/mix.lock* ./

RUN mix deps.get --only prod

# Compile-time config only; runtime.exs is copied after assets.deploy.
COPY test_apps/phx_minimal/config/config.exs test_apps/phx_minimal/config/prod.exs config/

RUN mix deps.compile

RUN mix assets.setup

COPY test_apps/phx_minimal/priv priv
COPY test_apps/phx_minimal/lib lib

RUN mix compile

COPY test_apps/phx_minimal/assets assets

RUN mix assets.deploy

# Changes to runtime.exs do not require recompiling or rebuilding assets.
COPY test_apps/phx_minimal/config/runtime.exs config/

RUN mix release

FROM ${RUNNER_IMAGE}

RUN apk add --no-cache libstdc++ ncurses-libs openssl

WORKDIR /app

ENV MIX_ENV=prod
ENV PHX_SERVER=true
ENV PORT=4000
ENV DATABASE_PATH=/app/phx_minimal.db

EXPOSE 4000

COPY --from=builder /build/test_apps/phx_minimal/_build/prod/rel/phx_minimal ./

CMD ["bin/phx_minimal", "start"]
