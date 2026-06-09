#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Validate an AssureLoop release manifest against its JSON Schema."""

from __future__ import annotations

import argparse
import datetime as dt
import json
from pathlib import Path
import re
import sys
from typing import Any


DEFAULT_SCHEMA = Path("schemas/release-manifest.schema.json")


def json_type_name(value: Any) -> str:
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "boolean"
    if isinstance(value, int):
        return "integer"
    if isinstance(value, float):
        return "number"
    if isinstance(value, str):
        return "string"
    if isinstance(value, list):
        return "array"
    if isinstance(value, dict):
        return "object"
    return type(value).__name__


def matches_type(value: Any, expected: str) -> bool:
    if expected == "object":
        return isinstance(value, dict)
    if expected == "array":
        return isinstance(value, list)
    if expected == "string":
        return isinstance(value, str)
    if expected == "integer":
        return isinstance(value, int) and not isinstance(value, bool)
    if expected == "number":
        return isinstance(value, (int, float)) and not isinstance(value, bool)
    if expected == "boolean":
        return isinstance(value, bool)
    if expected == "null":
        return value is None
    return True


def is_date_time(value: str) -> bool:
    if not value:
        return False
    candidate = value[:-1] + "+00:00" if value.endswith("Z") else value
    try:
        dt.datetime.fromisoformat(candidate)
    except ValueError:
        return False
    return True


def validate(instance: Any, schema: dict[str, Any], path: str = "$") -> list[str]:
    errors: list[str] = []

    expected_type = schema.get("type")
    if isinstance(expected_type, str) and not matches_type(instance, expected_type):
        return [f"{path}: expected {expected_type}, got {json_type_name(instance)}"]

    if "const" in schema and instance != schema["const"]:
        errors.append(f"{path}: expected constant {schema['const']!r}, got {instance!r}")

    enum = schema.get("enum")
    if isinstance(enum, list) and instance not in enum:
        errors.append(f"{path}: value {instance!r} is not one of {enum!r}")

    if isinstance(instance, str):
        min_length = schema.get("minLength")
        if isinstance(min_length, int) and len(instance) < min_length:
            errors.append(f"{path}: string length must be at least {min_length}")
        pattern = schema.get("pattern")
        if isinstance(pattern, str) and re.fullmatch(pattern, instance) is None:
            errors.append(f"{path}: value {instance!r} does not match pattern {pattern!r}")
        if schema.get("format") == "date-time" and not is_date_time(instance):
            errors.append(f"{path}: value {instance!r} is not a valid RFC 3339 date-time")

    if isinstance(instance, int) and not isinstance(instance, bool):
        minimum = schema.get("minimum")
        if isinstance(minimum, (int, float)) and instance < minimum:
            errors.append(f"{path}: value must be greater than or equal to {minimum}")

    if isinstance(instance, list):
        min_items = schema.get("minItems")
        if isinstance(min_items, int) and len(instance) < min_items:
            errors.append(f"{path}: array must contain at least {min_items} item(s)")
        item_schema = schema.get("items")
        if isinstance(item_schema, dict):
            for index, item in enumerate(instance):
                errors.extend(validate(item, item_schema, f"{path}[{index}]"))

    if isinstance(instance, dict):
        required = schema.get("required", [])
        if isinstance(required, list):
            for key in required:
                if isinstance(key, str) and key not in instance:
                    errors.append(f"{path}: missing required property {key!r}")

        properties = schema.get("properties", {})
        if isinstance(properties, dict):
            for key, property_schema in properties.items():
                if key in instance and isinstance(property_schema, dict):
                    errors.extend(validate(instance[key], property_schema, f"{path}.{key}"))

        additional = schema.get("additionalProperties", True)
        if additional is False and isinstance(properties, dict):
            allowed = set(properties)
            for key in instance:
                if key not in allowed:
                    errors.append(f"{path}: unexpected property {key!r}")
        elif isinstance(additional, dict) and isinstance(properties, dict):
            for key, value in instance.items():
                if key not in properties:
                    errors.extend(validate(value, additional, f"{path}.{key}"))

    return errors


def load_json(path: Path, label: str) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        raise SystemExit(f"ERROR: {label} not found: {path}") from None
    except json.JSONDecodeError as exc:
        raise SystemExit(f"ERROR: {label} is not valid JSON: {path}:{exc.lineno}:{exc.colno}: {exc.msg}") from None


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--schema", type=Path, default=DEFAULT_SCHEMA)
    args = parser.parse_args(argv)

    manifest = load_json(args.manifest, "manifest")
    schema = load_json(args.schema, "schema")
    if not isinstance(schema, dict):
        print(f"ERROR: schema root must be a JSON object: {args.schema}", file=sys.stderr)
        return 1

    errors = validate(manifest, schema)
    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1

    print(f"validated {args.manifest} against {args.schema}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
