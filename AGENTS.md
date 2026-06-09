# AssureLoop agent instructions

This repository is being developed by a founder/tester, a senior architect, and Codex as senior engineer.

## Mission

Build an open-source secure release assurance platform for Zephyr-based embedded controllers. The first milestone is not certification and not a new OS. The first milestone is a credible release workflow that produces firmware, an SBOM, a manifest, signatures, trace data, and evidence.

## Engineering rules

1. Prefer small reviewable changes.
2. Do not add board support unless an issue explicitly asks for it.
3. Do not introduce proprietary dependencies in the open-source core.
4. Every security feature must document its threat model and limitations.
5. Every release artifact must be reproducible or explain why it is intentionally time-bound.
6. Use SPDX license identifiers in source files.
7. C code must avoid dynamic allocation in the controller loop.
8. Treat `docs/codex-backlog.md` as the current implementation backlog.
9. Do not claim safety or cybersecurity certification unless we have exact-scope evidence.
10. Keep public APIs boring and explicit.

## Definition of done

A task is done when it has:

- working code or clearly marked documentation,
- a test or manual verification path,
- updated docs if behavior changed,
- no unsupported certification/security claims.
