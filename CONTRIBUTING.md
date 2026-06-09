# Contributing

Thank you for helping build AssureLoop.

## Development flow

1. Open or pick a small issue.
2. Create a branch with a focused name.
3. Keep implementation and formatting changes separate.
4. Add or update tests where possible.
5. Update docs when behavior or workflows change.
6. Submit a pull request using the template.

## Commit style

Use concise conventional-style prefixes when useful:

```text
arch: document release architecture
tools: add manifest verification
firmware: add loop jitter telemetry
ci: add host tooling workflow
```

## Security-sensitive changes

Security-sensitive changes require a threat-model note. Do not merge security behavior based only on happy-path tests.

## Certification language

Use these words carefully:

- Acceptable: evidence, audit support, certification-ready, reference process, traceability aid.
- Not acceptable without formal scope: certified, compliant, approved, safety-certified, CRA-compliant, IEC 62443-certified.
