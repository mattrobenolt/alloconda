# Publishing docs

Alloconda docs are built with mdBook. The output directory is configured as `book/`.

## Cloudflare Pages (Git integration)

Use Cloudflare Pages with Git integration and set the build settings:

- Build command: `mdbook build`
- Build output directory: `book`
- Root directory: repo root (where `book.toml` lives)

If you change `[build].build-dir` in `book.toml`, update the Pages build output
to match.

## Local preview

```bash
mdbook serve
```
