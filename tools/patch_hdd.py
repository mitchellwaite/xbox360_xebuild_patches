#!/usr/bin/env python3
"""
hex_replace.py

Recursively scans a directory for files containing a given byte sequence
(specified as hex) and replaces every occurrence with a different byte
sequence (also specified as hex).

Works on Windows with a standard python3 interpreter -- no third-party
dependencies required.

USAGE:
    python hex_replace.py <directory> [--dry-run] [--backup] [--ext .bin .xex]

EXAMPLES:
    # Preview what would change, without touching any files
    python hex_replace.py C:\path\to\folder --dry-run

    # Actually perform the replacement, keeping a .bak copy of each
    # modified file
    python hex_replace.py C:\path\to\folder --backup

    # Only touch files with certain extensions
    python hex_replace.py C:\path\to\folder --ext .xex .bin
"""

import argparse
import os
import sys

# ----------------------------------------------------------------------
# Edit these two lines if you want to hardcode the pattern instead of
# passing it on the command line. As given, FIND and REPLACE are already
# set from your request.
# 
# ----------------------------------------------------------------------
DEFAULT_FIND = "00 12 83 78 00 00 00 02 38 60 00 01 4E 80 00 20"
DEFAULT_REPLACE = (
    "00 12 83 B8 00 00 00 01 48 00 01 60 "
    "00 12 84 DC 00 00 00 01 38 60 00 01 "
    "00 12 85 18 00 00 00 01 38 60 00 01"
)


def hex_to_bytes(hex_string: str) -> bytes:
    """Convert a whitespace-separated hex string like '00 15 D9' to bytes."""
    cleaned = hex_string.replace(",", " ").split()
    try:
        return bytes(int(b, 16) for b in cleaned)
    except ValueError as e:
        raise ValueError(f"Invalid hex byte in pattern: {e}")


def scan_and_replace(root_dir, find_bytes, replace_bytes, dry_run=False,
                      backup=False, extensions=None):
    total_files_scanned = 0
    total_files_modified = 0
    total_replacements = 0

    for dirpath, _dirnames, filenames in os.walk(root_dir):
        for filename in filenames:
            if extensions and not filename.lower().endswith(tuple(extensions)):
                continue

            filepath = os.path.join(dirpath, filename)
            total_files_scanned += 1

            try:
                with open(filepath, "rb") as f:
                    data = f.read()
            except (PermissionError, OSError) as e:
                print(f"  [SKIP] Could not read {filepath}: {e}")
                continue

            count = data.count(find_bytes)
            if count == 0:
                continue

            new_data = data.replace(find_bytes, replace_bytes)
            total_files_modified += 1
            total_replacements += count

            print(f"  [MATCH] {filepath}  ({count} occurrence{'s' if count != 1 else ''})")

            if dry_run:
                continue

            if backup:
                backup_path = filepath + ".bak"
                try:
                    with open(backup_path, "wb") as bf:
                        bf.write(data)
                except OSError as e:
                    print(f"    [WARN] Failed to write backup for {filepath}: {e}")
                    continue

            try:
                with open(filepath, "wb") as f:
                    f.write(new_data)
            except OSError as e:
                print(f"    [ERROR] Failed to write {filepath}: {e}")
                continue

    return total_files_scanned, total_files_modified, total_replacements


def main():
    parser = argparse.ArgumentParser(
        description="Recursively find/replace a hex byte pattern across files."
    )
    parser.add_argument("directory", help="Root directory to scan recursively")
    parser.add_argument(
        "--find", default=DEFAULT_FIND,
        help="Hex bytes to search for, space-separated (default: built-in pattern)"
    )
    parser.add_argument(
        "--replace", default=DEFAULT_REPLACE,
        help="Hex bytes to replace with, space-separated (default: built-in pattern)"
    )
    parser.add_argument(
        "--dry-run", action="store_true",
        help="Show what would be changed without modifying any files"
    )
    parser.add_argument(
        "--backup", action="store_true",
        help="Save a .bak copy of each file before modifying it"
    )
    parser.add_argument(
        "--ext", nargs="*", default=None,
        help="Only process files with these extensions, e.g. --ext .xex .bin"
    )
    args = parser.parse_args()

    if not os.path.isdir(args.directory):
        print(f"Error: '{args.directory}' is not a valid directory.")
        sys.exit(1)

    find_bytes = hex_to_bytes(args.find)
    replace_bytes = hex_to_bytes(args.replace)

    print(f"Scanning: {args.directory}")
    print(f"Find    ({len(find_bytes)} bytes): {find_bytes.hex(' ').upper()}")
    print(f"Replace ({len(replace_bytes)} bytes): {replace_bytes.hex(' ').upper()}")
    if len(find_bytes) != len(replace_bytes):
        print("Note: pattern lengths differ -- files will grow/shrink accordingly.")
    if args.dry_run:
        print("Mode: DRY RUN (no files will be modified)\n")
    else:
        print(f"Mode: LIVE{' (backups enabled)' if args.backup else ''}\n")

    scanned, modified, replacements = scan_and_replace(
        args.directory, find_bytes, replace_bytes,
        dry_run=args.dry_run, backup=args.backup, extensions=args.ext
    )

    print(f"\nDone. Scanned {scanned} file(s), "
          f"{'would modify' if args.dry_run else 'modified'} {modified} file(s), "
          f"{replacements} total occurrence(s) replaced.")


if __name__ == "__main__":
    main()