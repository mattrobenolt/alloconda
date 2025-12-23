# Contributing

This section covers alloconda development and repository maintenance. The repo
is intentionally opinionated: we use Nix, direnv, and the Justfile.

Repo: <https://github.com/mattrobenolt/alloconda>

## Tooling

Recommended setup:

- Nix (flake-enabled).
- direnv.

`direnv` loads the Nix dev shell automatically. From the repo root:

```bash
direnv allow
```

If you prefer to avoid direnv:

```bash
nix develop
```

The dev shell provides Zig 0.15, Python 3.14, uv, mdBook, wrangler, and other
tools used in this repo.

## Workspace setup

Install dependencies for all workspace members:

```bash
just sync
```

This runs `uv sync --all-packages --all-groups --all-extras` under the hood.

## Running tests and lint

Run the example module tests:

```bash
just zigadd
just zigzon
```

Run everything CI checks:

```bash
just ci
```

Lint the repo:

```bash
just lint
```

Type-check the CLI:

```bash
cd python/alloconda && ty check
```

## Example modules

The repo includes example extension modules:

- `python/zigadd`: a minimal extension with tests and type stubs.
- `python/zigzon`: a ZON codec example with tests and type stubs.

## Docs site

Docs are built with mdBook. The output directory is configured as `book/`.

Zig API docs are generated via the build system and copied into `docs/zig-docs`.
`just docs` runs both Zig docgen and mdBook. If Python headers are not detected
automatically, set `ALLOCONDA_PYTHON_INCLUDE`.

```bash
just docs
```

For local previews:

```bash
just docs-serve
```

Docs are deployed via GitHub Actions using Nix. The workflow runs
`nix develop --command just docs` and deploys with Wrangler. Configure the
Cloudflare Pages project for External CI and set these GitHub secrets:

- `CLOUDFLARE_API_TOKEN`
- `CLOUDFLARE_ACCOUNT_ID`

## Roadmap

The short-term roadmap lives in `PLAN.md` at the repo root.
