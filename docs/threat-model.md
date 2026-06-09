# Threat model

## Assets

- Firmware binaries.
- Release manifests.
- Signing keys.
- SBOM and build provenance.
- Trace and test evidence.
- Device update flow.

## Initial trust boundaries

```text
Developer workstation / CI
  ├── source checkout
  ├── Zephyr toolchain
  ├── build output
  ├── signing key access
  └── release bundle

Device / simulator
  ├── bootloader
  ├── application image
  ├── update storage
  └── runtime logs
```

## Threats considered in v0.1

| Threat | Current mitigation | Status |
|---|---|---|
| Artifact tampering after build | SHA-256 in release manifest | Implemented |
| Manifest tampering | OpenSSL manifest signature | Implemented for dev keys |
| Unknown source state | git commit and dirty hint | Implemented |
| Incomplete evidence | evidence bundle index | Implemented |
| Firmware downgrade | planned MCUboot rollback policy | Planned |
| Unsigned firmware boot | planned MCUboot integration | Planned |
| Compromised signing key | production key policy required | Not solved |
| Malicious dependency | SBOM generation and review workflow | Planned |

## Explicit non-goals for v0.1

- Formal safety certification.
- Formal CRA or IEC 62443 compliance claims.
- Production key custody.
- Remote fleet update service.
- Hardware root-of-trust integration.

## Security acceptance rule

A security feature is not accepted unless it documents:

1. what it protects,
2. what it does not protect,
3. how it fails,
4. how a tester can verify the behavior.
