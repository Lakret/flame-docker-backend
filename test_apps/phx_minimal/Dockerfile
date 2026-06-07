# Build from repo root: docker build -t phx_minimal:latest -f test_apps/phx_minimal/Dockerfile .
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

COPY mix.exs mix.lock ./
COPY lib lib

COPY test_apps/phx_minimal/mix.exs test_apps/phx_minimal/mix.lock* test_apps/phx_minimal/
COPY test_apps/phx_minimal/config test_apps/phx_minimal/config
COPY test_apps/phx_minimal/lib test_apps/phx_minimal/lib
COPY test_apps/phx_minimal/priv test_apps/phx_minimal/priv
COPY test_apps/phx_minimal/assets test_apps/phx_minimal/assets

WORKDIR /build/test_apps/phx_minimal

RUN mix deps.get --only prod
RUN mix deps.compile
RUN mix assets.deploy
RUN mix release

# ============ Runner Stage ============
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
