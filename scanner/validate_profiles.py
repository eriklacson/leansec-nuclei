#!/usr/bin/env python3
"""
Validate all tags in profiles.yaml against available Nuclei templates.

Usage:
    python3 validate_profiles.py [--profiles-file <path>] [--verbose]

Exit codes:
    0 — All profiles valid
    1 — One or more profiles have no matching templates
"""

import argparse
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Dict, List, Tuple

import yaml


def load_profiles(profiles_file: str) -> Dict:
    """Load profiles.yaml and return parsed structure."""
    try:
        with open(profiles_file, "r") as f:
            data = yaml.safe_load(f)
        return data
    except FileNotFoundError:
        print(f"❌ Error: profiles.yaml not found at {profiles_file}")
        sys.exit(1)
    except yaml.YAMLError as e:
        print(f"❌ Error parsing YAML: {e}")
        sys.exit(1)


def get_nuclei_templates(tags: List[str]) -> int:
    """
    Query Nuclei for templates matching the given tags.
    Returns the count of matching templates.
    """
    if not tags:
        return 0

    tags_str = ",".join(tags)

    # Resolve nuclei to an absolute path so the subprocess call doesn't rely on PATH lookup
    nuclei_bin = shutil.which("nuclei")
    if nuclei_bin is None:
        print("❌ Error: nuclei binary not found. Install with: brew install nuclei")
        sys.exit(1)

    try:
        # Static argv built from the validated YAML config — no shell, no user-controlled input
        result = subprocess.run(  # noqa: S603
            [nuclei_bin, "-tags", tags_str, "-list-templates"],
            capture_output=True,
            text=True,
            timeout=30,
        )

        # Count non-empty lines (each line is a template)
        templates = [line for line in result.stdout.strip().split("\n") if line]
        return len(templates)

    except FileNotFoundError:
        print("❌ Error: nuclei binary not found. Install with: brew install nuclei")
        sys.exit(1)
    except subprocess.TimeoutExpired:
        print("⚠ Warning: nuclei -list-templates timed out (30s). Network issue?")
        return -1
    except Exception as e:
        print(f"❌ Error running nuclei: {e}")
        sys.exit(1)


def validate_profiles(profiles_file: str, verbose: bool = False) -> Tuple[int, int]:
    """
    Validate all profiles in profiles.yaml.
    Returns (passed_count, failed_count).
    """
    data = load_profiles(profiles_file)

    if "profiles" not in data:
        print("❌ Error: 'profiles' key not found in profiles.yaml")
        sys.exit(1)

    profiles = data["profiles"]
    passed = 0
    failed = 0

    print(f"\n[*] Validating {len(profiles)} profiles from {profiles_file}\n")

    for profile_name, profile_config in profiles.items():
        if not isinstance(profile_config, dict):
            print(f"  ❌ {profile_name} — invalid configuration (not a dict)")
            failed += 1
            continue

        tags = profile_config.get("tags", [])

        if not tags:
            print(f"  ⚠ {profile_name} — no tags defined")
            failed += 1
            continue

        # Query Nuclei
        count = get_nuclei_templates(tags)

        if count == -1:
            print(f"  ⚠ {profile_name} — validation skipped (timeout)")
            continue

        if count == 0:
            tags_str = ", ".join(tags)
            print(f"  ❌ {profile_name} — no templates found")
            if verbose:
                print(f"      Tags: {tags_str}")
            failed += 1
        else:
            tags_str = ", ".join(tags)
            print(f"  ✅ {profile_name} — {count} templates found")
            if verbose:
                print(f"      Tags: {tags_str}")
            passed += 1

    print(f"\n[*] Results: {passed} passed, {failed} failed\n")
    return passed, failed


def main():
    # Resolve default profiles.yaml relative to this script, not the caller's CWD
    default_profiles = Path(__file__).resolve().parent / "profiles" / "profiles.yaml"

    parser = argparse.ArgumentParser(description="Validate Nuclei profile tags against available templates")
    parser.add_argument(
        "--profiles-file", default=str(default_profiles), help=f"Path to profiles.yaml (default: {default_profiles})"
    )
    parser.add_argument("--verbose", "-v", action="store_true", help="Print tag details for each profile")

    args = parser.parse_args()

    # Resolve the (possibly user-supplied) path to an absolute path before checking existence
    profiles_path = Path(args.profiles_file).expanduser().resolve()

    if not profiles_path.exists():
        print(f"❌ Error: {profiles_path} not found")
        sys.exit(1)

    passed, failed = validate_profiles(str(profiles_path), args.verbose)

    # Exit with error if any profiles failed
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
