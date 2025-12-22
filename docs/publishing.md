# Publishing docs

Alloconda docs are built with mdBook. The output directory is configured as `book/`.

## Cloudflare Pages (Git integration)

Use Cloudflare Pages with Git integration and set the build settings:

- Build command: `bash scripts/cloudflare/build-docs.sh`
- Build output directory: `book`
- Root directory: repo root (where `book.toml` lives)

If you change `[build].build-dir` in `book.toml`, update the Pages build output
to match.

The build script downloads mdBook and runs the build. You can override the
version by setting `MD_BOOK_VERSION` in the Pages build environment.

## Local preview

```bash
mdbook serve
```
