# Design Partner Feedback

## Purpose

AssureLoop is looking for early feedback from embedded firmware teams before it
moves from simulator-first and ST NUCLEO-H563ZI hardware-alpha validation toward
broader hardware and update workflows.

This is not production OTA, not production secure boot, and not certified safety
or cybersecurity compliance. The goal is to learn whether the release assurance
evidence is useful and what would block adoption.

## Firmware Release Process

- Would AssureLoop fit your current firmware release process?
- Where would it sit: developer workstation, CI, release manager machine, or
  product security review?
- Which parts of your release workflow are currently manual?
- What release artifacts must be approved before firmware can ship?
- Do Windows-first developers need the same commands as Linux CI?

## Evidence You Currently Collect

- What evidence do you currently collect for each firmware release?
- Do you store build logs, release manifests, hashes, binaries, map files, or
  trace logs?
- How do you prove which source revision produced a firmware image?
- Who reviews the release evidence: firmware, QA, security, safety, customer, or
  compliance teams?
- What evidence is missing or painful to reconstruct after a release?

## SBOM Needs

- Do you need SBOMs for embedded firmware releases?
- Which format do customers or internal reviewers ask for?
- Do you already generate SPDX or CycloneDX output?
- Should SBOM generation be mandatory, optional, or CI-only?
- What component metadata would make the SBOM more useful?

## Update Package Verification

- How do you handle update package verification today?
- Do you check payload hash, target compatibility, version downgrade, signature,
  or evidence bundle integrity before accepting an update?
- Where should downgrade policy live: package verifier, bootloader config,
  device state, or release process?
- What tamper scenarios should AssureLoop test next?
- Would a local simulator help you review update lifecycle behavior before real
  OTA transport exists?

## Adoption Blockers

- What would block adoption in your team?
- Are local development keys acceptable for demos if production key custody is
  clearly out of scope?
- Which missing board, update transport, CI integration, or evidence format
  would matter most?
- Does the workflow feel too heavy for small firmware teams?
- What needs to be documented before you would try it on a real project?
- What claims would make you distrust the project?

## Follow-Up Signals

The strongest design-partner feedback will identify:

- one concrete firmware release workflow AssureLoop should fit,
- one missing evidence artifact that matters,
- one verification check that should be stricter,
- one setup or tooling obstacle,
- one claim that must stay clearly out of scope.
