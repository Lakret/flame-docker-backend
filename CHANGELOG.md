# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0]

Initial release.

### Added

- `FLAMEDockerBackend`, a `FLAME.Backend` that provisions runners as Docker
  containers via the Docker Engine API (Docker-out-of-Docker).
- `FLAMEDockerBackend.DockerAPI`, a thin `:httpc`-based client over the Docker
  Engine API Unix socket.
- Cross-platform socket detection for Linux, macOS (Docker Desktop), and WSL2.
- Image pull on demand when the configured image is missing locally.
- Configuration passthrough for `:host_config`, `:mounts`, and `:cmd`, plus
  `:env`, `:boot_timeout`, `:keep_runners`, and `:docker_socket_path`.
- Forwarding of `ERL_AFLAGS` and `ERL_ZFLAGS` from parent to runners.

[0.1.0]: https://github.com/Lakret/flame-docker-backend/releases/tag/v0.1.0
