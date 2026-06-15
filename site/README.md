# AssureLoop Static Site

This directory contains the static landing page for
[assureloop.dev](https://assureloop.dev/).

The site is intentionally small:

- no backend,
- no analytics,
- no cookies,
- no user accounts,
- no build step.

## Local Preview

Open `site/index.html` directly in a browser, or serve the directory with any
static file server:

```powershell
py -m http.server 8000 -d site
```

Then visit `http://localhost:8000`.

## Deployment

GitHub Pages deploys the contents of `site/` using
`.github/workflows/pages.yml`.

The custom domain is configured by `site/CNAME`:

```text
assureloop.dev
```

See `docs/assureloop-dev-domain-setup.md` for DNS and HTTPS setup notes.
