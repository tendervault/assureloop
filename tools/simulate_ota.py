#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Simulate a local firmware OTA staging/install/rollback lifecycle."""

from __future__ import annotations

import argparse
import datetime as dt
import json
from pathlib import Path
import sys
from typing import Any

from verify_update_package import verify_package


DEFAULT_SCHEMA = Path("schemas/release-manifest.schema.json")
DEFAULT_STATE = Path("dist/ota-sim/state.json")
DEFAULT_CURRENT_VERSION = "0.0.0"
ACTIONS = ("stage", "install", "confirm", "rollback", "status")


def generated_at() -> str:
    return (
        dt.datetime.now(dt.timezone.utc)
        .replace(microsecond=0)
        .isoformat()
        .replace("+00:00", "Z")
    )


def default_state(target: str | None, installed_version: str | None) -> dict[str, Any]:
    version = installed_version or DEFAULT_CURRENT_VERSION
    return {
        "schema_version": "0.1.0",
        "current_version": version,
        "previous_version": None,
        "previous_package": None,
        "target": target,
        "staged_package": None,
        "staged_version": None,
        "installed_package": None,
        "installed_version": version,
        "confirmed": True,
        "rollback_available": False,
        "last_error": None,
        "history": [],
    }


def normalize_state(state: dict[str, Any], target: str | None, installed_version: str | None) -> dict[str, Any]:
    normalized = default_state(target, installed_version)
    normalized.update(state)

    if not isinstance(normalized.get("history"), list):
        normalized["history"] = []

    if normalized.get("target") is None and target is not None:
        normalized["target"] = target

    if normalized.get("current_version") is None:
        normalized["current_version"] = installed_version or DEFAULT_CURRENT_VERSION
    if normalized.get("installed_version") is None:
        normalized["installed_version"] = normalized["current_version"]

    return normalized


def load_state(path: Path, target: str | None, installed_version: str | None) -> dict[str, Any]:
    if not path.exists():
        return default_state(target, installed_version)

    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise SystemExit(
            f"ERROR: simulator state is not valid JSON: {path}:{exc.lineno}:{exc.colno}: {exc.msg}"
        ) from None

    if not isinstance(raw, dict):
        raise SystemExit(f"ERROR: simulator state root must be a JSON object: {path}")

    return normalize_state(raw, target, installed_version)


def save_state(path: Path, state: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp_path = path.with_name(f"{path.name}.tmp")
    temp_path.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    temp_path.replace(path)


def record_history(
    state: dict[str, Any],
    action: str,
    result: str,
    *,
    package_path: Path | None = None,
    version: str | None = None,
    error: str | None = None,
) -> None:
    history = state.setdefault("history", [])
    if not isinstance(history, list):
        history = []
        state["history"] = history

    entry: dict[str, Any] = {
        "timestamp": generated_at(),
        "action": action,
        "result": result,
    }
    if package_path is not None:
        entry["package"] = str(package_path)
    if version is not None:
        entry["version"] = version
    if error is not None:
        entry["error"] = error
    history.append(entry)


def effective_target(state: dict[str, Any], requested_target: str | None) -> str | None:
    if requested_target is not None:
        return requested_target
    target = state.get("target")
    return target if isinstance(target, str) and target else None


def effective_installed_version(state: dict[str, Any], requested_version: str | None) -> str | None:
    if requested_version is not None:
        return requested_version
    version = state.get("current_version") or state.get("installed_version")
    return version if isinstance(version, str) and version else None


def verify_update(
    package_dir: Path,
    schema: Path,
    installed_version: str | None,
    target: str | None,
    allow_downgrade: bool,
) -> tuple[dict[str, Any], list[str]]:
    try:
        return verify_package(
            package_dir=package_dir,
            schema=schema,
            installed_version=None if allow_downgrade else installed_version,
            target=target,
        )
    except SystemExit as exc:
        return {}, [str(exc)]


def fail_action(
    state_path: Path,
    state: dict[str, Any],
    action: str,
    message: str,
    *,
    package_path: Path | None = None,
    version: str | None = None,
) -> int:
    state["last_error"] = message
    record_history(
        state,
        action,
        "FAIL",
        package_path=package_path,
        version=version,
        error=message,
    )
    save_state(state_path, state)
    print(f"ERROR: {message}", file=sys.stderr)
    print_status(state, state_path=state_path, action=action, result="FAIL")
    return 1


def stage_package(args: argparse.Namespace, state: dict[str, Any]) -> int:
    if args.package is None:
        return fail_action(args.state, state, "stage", "--package is required for stage")

    package_dir = args.package.resolve()
    installed_version = effective_installed_version(state, args.installed_version)
    target = effective_target(state, args.target)
    package, errors = verify_update(
        package_dir=package_dir,
        schema=args.schema.resolve(),
        installed_version=installed_version,
        target=target,
        allow_downgrade=args.allow_downgrade,
    )

    package_version = package.get("version") if isinstance(package, dict) else None
    version = package_version if isinstance(package_version, str) else None
    if errors:
        return fail_action(
            args.state,
            state,
            "stage",
            "; ".join(errors),
            package_path=package_dir,
            version=version,
        )

    state["target"] = package.get("target") or target
    state["staged_package"] = str(package_dir)
    state["staged_version"] = version
    state["last_error"] = None
    record_history(state, "stage", "PASS", package_path=package_dir, version=version)
    save_state(args.state, state)
    print_status(state, state_path=args.state, action="stage", result="PASS")
    return 0


def install_package(args: argparse.Namespace, state: dict[str, Any]) -> int:
    staged_package = state.get("staged_package")
    if not isinstance(staged_package, str) or not staged_package:
        return fail_action(args.state, state, "install", "no staged package is available")

    package_dir = Path(staged_package).resolve()
    installed_version = effective_installed_version(state, args.installed_version)
    target = effective_target(state, args.target)
    package, errors = verify_update(
        package_dir=package_dir,
        schema=args.schema.resolve(),
        installed_version=installed_version,
        target=target,
        allow_downgrade=args.allow_downgrade,
    )

    package_version = package.get("version") if isinstance(package, dict) else None
    version = package_version if isinstance(package_version, str) else None
    if errors:
        return fail_action(
            args.state,
            state,
            "install",
            "; ".join(errors),
            package_path=package_dir,
            version=version,
        )

    state["previous_version"] = state.get("current_version")
    state["previous_package"] = state.get("installed_package")
    state["current_version"] = version
    state["installed_package"] = str(package_dir)
    state["installed_version"] = version
    state["confirmed"] = False
    state["rollback_available"] = True
    state["staged_package"] = None
    state["staged_version"] = None
    state["target"] = package.get("target") or target
    state["last_error"] = None
    record_history(state, "install", "PASS", package_path=package_dir, version=version)
    save_state(args.state, state)
    print_status(state, state_path=args.state, action="install", result="PASS")
    return 0


def confirm_install(args: argparse.Namespace, state: dict[str, Any]) -> int:
    installed_package = state.get("installed_package")
    if not installed_package:
        return fail_action(args.state, state, "confirm", "no installed package is available")

    if state.get("confirmed") is True and state.get("rollback_available") is not True:
        return fail_action(args.state, state, "confirm", "installed package is already confirmed")

    state["confirmed"] = True
    state["rollback_available"] = False
    state["previous_version"] = None
    state["previous_package"] = None
    state["last_error"] = None
    version = state.get("installed_version") if isinstance(state.get("installed_version"), str) else None
    record_history(state, "confirm", "PASS", package_path=Path(str(installed_package)), version=version)
    save_state(args.state, state)
    print_status(state, state_path=args.state, action="confirm", result="PASS")
    return 0


def rollback_install(args: argparse.Namespace, state: dict[str, Any]) -> int:
    if state.get("rollback_available") is not True:
        return fail_action(args.state, state, "rollback", "rollback is not available")

    previous_version = state.get("previous_version")
    if not isinstance(previous_version, str) or not previous_version:
        return fail_action(args.state, state, "rollback", "previous_version is not available")

    rolled_back_from = state.get("current_version")
    state["current_version"] = previous_version
    state["installed_version"] = previous_version
    state["installed_package"] = state.get("previous_package")
    state["previous_version"] = None
    state["previous_package"] = None
    state["confirmed"] = True
    state["rollback_available"] = False
    state["staged_package"] = None
    state["staged_version"] = None
    state["last_error"] = None
    record_history(
        state,
        "rollback",
        "PASS",
        version=previous_version,
        error=f"rolled back from {rolled_back_from}",
    )
    save_state(args.state, state)
    print_status(state, state_path=args.state, action="rollback", result="PASS")
    return 0


def print_status(
    state: dict[str, Any],
    *,
    state_path: Path,
    action: str = "status",
    result: str = "PASS",
) -> None:
    history = state.get("history")
    history_count = len(history) if isinstance(history, list) else 0
    print(f"action: {action}")
    print(f"result: {result}")
    print(f"state: {state_path}")
    print(f"target: {state.get('target') or 'unknown'}")
    print(f"current_version: {state.get('current_version') or 'unknown'}")
    print(f"previous_version: {state.get('previous_version') or 'none'}")
    print(f"staged_package: {state.get('staged_package') or 'none'}")
    print(f"staged_version: {state.get('staged_version') or 'none'}")
    print(f"installed_package: {state.get('installed_package') or 'none'}")
    print(f"installed_version: {state.get('installed_version') or 'unknown'}")
    print(f"confirmed: {str(state.get('confirmed')).lower()}")
    print(f"rollback_available: {str(state.get('rollback_available')).lower()}")
    print(f"last_error: {state.get('last_error') or 'none'}")
    print(f"history_count: {history_count}")


def parse_args(argv: list[str] | None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action_name", nargs="?", choices=ACTIONS)
    parser.add_argument("--action", choices=ACTIONS)
    parser.add_argument("--package", type=Path)
    parser.add_argument("--state", type=Path, default=DEFAULT_STATE)
    parser.add_argument("--schema", type=Path, default=DEFAULT_SCHEMA)
    parser.add_argument("--target")
    parser.add_argument("--installed-version")
    parser.add_argument(
        "--allow-downgrade",
        action="store_true",
        help="Allow staging/installing a package older than the installed version.",
    )
    args = parser.parse_args(argv)

    selected_action = args.action or args.action_name
    if selected_action is None:
        parser.error("an action is required; pass --action or use stage|install|confirm|rollback|status")
    args.action = selected_action
    return args


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    state_path = args.state.resolve()
    args.state = state_path

    try:
        state = load_state(state_path, args.target, args.installed_version)
    except SystemExit as exc:
        print(exc, file=sys.stderr)
        return 1

    if args.action == "status":
        print_status(state, state_path=state_path)
        return 0
    if args.action == "stage":
        return stage_package(args, state)
    if args.action == "install":
        return install_package(args, state)
    if args.action == "confirm":
        return confirm_install(args, state)
    if args.action == "rollback":
        return rollback_install(args, state)

    raise AssertionError(f"unhandled action: {args.action}")


if __name__ == "__main__":
    raise SystemExit(main())
