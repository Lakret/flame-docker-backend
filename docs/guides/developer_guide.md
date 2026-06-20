# Developer Guide

This guide covers the release process for `flame_docker_backend`.

## Release Model

Releases are tag-driven. A tag like `v0.1.0` starts the release workflow, which:

1. Runs the same unit-test setup used by CI.
2. Runs the Docker integration tests.
3. Verifies the tag matches `@version` in `mix.exs`.
4. Builds docs and the Hex package.
5. Publishes the package and docs to Hex.pm.
6. Creates a GitHub Release and attaches the Hex tarball.

Normal pushes to `main` do not publish to Hex.pm.

## One-Time Setup

Create a Hex.pm API key with publish permissions:

```bash
mix hex.user key generate --key-name publish-ci --permission api:write
```

Add the key as a GitHub Actions repository secret:

```text
HEX_API_KEY
```

The workflow reads this secret when running `mix hex.publish --yes`.

## Prepare a Release

Update the package version in `mix.exs`:

```elixir
@version "0.1.0"
```

Update `CHANGELOG.md` with the release notes for the same version.

Before tagging, verify the package locally:

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix test
mix docs
mix hex.build
```

Run Docker integration tests when Docker is available:

```bash
MIX_ENV=test mix test.docker
```

## Publish a Release

Commit the version and changelog changes:

```bash
git add mix.exs CHANGELOG.md
git commit -m "Release v0.1.0"
```

Create and push a matching tag:

```bash
git tag v0.1.0
git push origin main
git push origin v0.1.0
```

The tag must match `mix.exs` exactly. For example, `@version "0.1.0"` must use
tag `v0.1.0`. If they differ, the release workflow stops before publishing.

## If Publishing Fails

Hex package versions are immutable after the publish window. If a release fails
before `mix hex.publish --yes`, fix the problem and push a new tag or rerun the
workflow.

If Hex publishing succeeds but GitHub Release creation fails, create the GitHub
Release manually from the same tag. Do not publish a second Hex version unless
the package contents need to change.

If a bad package is published, check Hex.pm's revert rules quickly. Hex only
allows reverting recent versions for a short time.
