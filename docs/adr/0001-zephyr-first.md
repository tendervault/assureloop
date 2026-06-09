# ADR 0001: Use Zephyr as the first RTOS base

Date: 2026-06-09

## Status

Accepted.

## Context

AssureLoop is targeting connected industrial controllers and robotics-adjacent embedded devices. The commercial gap is release assurance, updateability, SBOMs, traceability, and maintainability, not a new scheduler or kernel.

## Decision

Use Zephyr as the first open-source RTOS base.

## Consequences

Positive:

- strong embedded ecosystem,
- west/CMake/Kconfig/devicetree workflow,
- official SPDX generation path,
- MCUboot integration path,
- good fit for controller-class devices.

Negative:

- Zephyr complexity may slow beginner onboarding,
- board support can sprawl,
- safety/certification remains system-context-specific.

## Guardrail

Do not add an alternative RTOS before the Zephyr release workflow is credible.
