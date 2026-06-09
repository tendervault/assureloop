# Security Policy

AssureLoop is pre-production. Please do not deploy it in safety-critical or security-critical products yet.

## Reporting vulnerabilities

For now, open a private maintainer contact channel before publicizing a vulnerability. When the public repository is created, this file should be updated with a dedicated reporting email and GitHub Security Advisories instructions.

## Supported versions

No stable versions are supported yet.

| Version | Supported |
|---|---|
| 0.1-dev | No production support |

## Security posture

The project aims to support:

- signed release manifests,
- firmware signing integration,
- SBOM generation,
- vulnerability response evidence,
- reproducible build metadata,
- traceability between requirements and tests.

Current limitations:

- no formal certification,
- no production key-management process,
- MCUboot integration is scaffolded but not complete,
- no field OTA transport implementation yet.
