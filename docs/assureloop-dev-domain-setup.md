# assureloop.dev Domain Setup

## Purpose

This document records the GitHub Pages setup for the public AssureLoop landing
page at `https://assureloop.dev/`.

The site is static. It does not use a backend, analytics, cookies, a database,
or user accounts.

## GitHub Pages Setup

1. In GitHub, open `tendervault/assureloop`.
2. Go to **Settings** > **Pages**.
3. Set **Source** to **GitHub Actions**.
4. Confirm `.github/workflows/pages.yml` has run successfully.
5. Under **Custom domain**, enter:

   ```text
   assureloop.dev
   ```

6. Keep `site/CNAME` committed with:

   ```text
   assureloop.dev
   ```

GitHub recommends adding the custom domain in the repository before configuring
DNS to reduce takeover risk. Official reference:
<https://docs.github.com/en/pages/configuring-a-custom-domain-for-your-github-pages-site/managing-a-custom-domain-for-your-github-pages-site>

## DNS Records

Configure these records at the registrar or DNS provider for `assureloop.dev`.

For the apex domain:

| Type | Name | Value |
|---|---|---|
| `A` | `@` | `185.199.108.153` |
| `A` | `@` | `185.199.109.153` |
| `A` | `@` | `185.199.110.153` |
| `A` | `@` | `185.199.111.153` |

Optional IPv6 records:

| Type | Name | Value |
|---|---|---|
| `AAAA` | `@` | `2606:50c0:8000::153` |
| `AAAA` | `@` | `2606:50c0:8001::153` |
| `AAAA` | `@` | `2606:50c0:8002::153` |
| `AAAA` | `@` | `2606:50c0:8003::153` |

Recommended `www` redirect support:

| Type | Name | Value |
|---|---|---|
| `CNAME` | `www` | `tendervault.github.io` |

Do not add wildcard DNS records such as `*.assureloop.dev`.

## HTTPS

After DNS resolves correctly, return to **Settings** > **Pages** and enable
**Enforce HTTPS** when GitHub makes the option available. GitHub notes that DNS
changes can take up to 24 hours to propagate, and HTTPS availability can take
additional time after the custom domain is configured.

## Verify The Domain

PowerShell:

```powershell
Resolve-DnsName assureloop.dev -Type A
Resolve-DnsName assureloop.dev -Type AAAA
Resolve-DnsName www.assureloop.dev -Type CNAME
```

Git Bash or Linux:

```bash
dig assureloop.dev +noall +answer -t A
dig assureloop.dev +noall +answer -t AAAA
dig www.assureloop.dev +noall +answer -t CNAME
```

Browser checks:

1. Open `https://assureloop.dev/`.
2. Confirm the page title is `AssureLoop | Release assurance for embedded firmware`.
3. Confirm browser security shows a valid HTTPS connection.
4. Open `https://www.assureloop.dev/` and confirm it redirects or resolves to
   the same site according to the GitHub Pages custom-domain setting.

## Troubleshooting

- If GitHub Pages reports a custom-domain error, confirm the domain is set to
  `assureloop.dev` in repository Pages settings.
- If DNS does not resolve, wait for propagation and confirm the A records are
  present at the active DNS provider.
- If HTTPS cannot be enforced yet, wait and refresh the Pages settings later.
- If `www.assureloop.dev` fails, confirm the `www` CNAME points to
  `tendervault.github.io` without the repository name.
- If a parked-domain or registrar page still appears, remove conflicting
  registrar default records.
- If there is a takeover warning, verify the domain in GitHub and remove any
  wildcard DNS records.
