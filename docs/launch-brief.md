# AssureLoop Launch Brief

## What AssureLoop Is

AssureLoop is open-source release assurance tooling for Zephyr-based embedded
firmware. It helps teams produce and verify the artifacts around a firmware
release: signed images, SBOM output, release manifests, trace reports, evidence
bundles, update packages, and local lifecycle validation.

The first public milestone is about release evidence and repeatable developer
workflow. AssureLoop is not a new operating system, not a production OTA
transport, not production secure boot, and not certified safety or cybersecurity
compliance.

## What v0.3 Proves

v0.3 hardware-alpha proves a narrow but real path:

- Zephyr simulator workflows build and produce release evidence.
- Firmware artifacts are captured in a machine-validated release manifest.
- Evidence bundles and update packages can be verified locally.
- SBOM files can be included in firmware evidence.
- MCUboot-compatible signed images can be produced with local development keys.
- ST NUCLEO-H563ZI hardware can boot the AssureLoop demo through MCUboot.
- The NUCLEO-H563ZI direct-flash lifecycle path has sample evidence for
  confirmed update, rollback, tamper rejection, and lower-version rejection.

This is hardware-alpha evidence for one supported board:
`ST NUCLEO-H563ZI` / Zephyr target `nucleo_h563zi`.

## Who Should Care

AssureLoop is meant for:

- embedded firmware teams who need a clearer release evidence trail,
- founders building controller products and preparing for customer review,
- maintainers who want boring, auditable firmware release artifacts,
- security-minded reviewers who care about SBOMs, hashes, manifests, and update
  package checks,
- early design partners who can shape the release assurance workflow before
  production claims are made.

## Feedback We Want

Useful feedback right now:

- Does the evidence bundle match what your team would need for release review?
- Are the manifest fields and artifact kinds understandable?
- Is the SBOM workflow practical for your Zephyr projects?
- Are update package verification checks aligned with your release gates?
- What evidence would a customer, auditor, or internal security reviewer ask
  for next?
- What would make the workflow too hard to adopt on Windows or Linux?
- Which board or update transport should be evaluated after the current
  simulator-first and NUCLEO-H563ZI path?

## What Not To Claim

Do not claim that AssureLoop is:

- a production OTA system,
- production secure boot,
- a certified safety product,
- a certified cybersecurity product,
- a replacement for Zephyr, MCUboot, or a product-specific security program,
- broad hardware support beyond the documented hardware-alpha board,
- a production signing-key custody or secure manufacturing solution.

The correct claim is narrower: AssureLoop is an open-source release assurance
workflow for auditable embedded firmware evidence, currently proven in simulator
flows and hardware-alpha validation on ST NUCLEO-H563ZI.
