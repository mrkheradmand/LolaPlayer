#!/usr/bin/env python3
"""Reject compiler versions outside the validated Swift 6.4 release line."""
import re
import subprocess


def validate(output):
    match = re.search(r'\bSwift version (\d+)\.(\d+)(?:\.(\d+))?', output)
    if not match:
        raise ValueError('Cannot identify the active Swift compiler version')
    if tuple(map(int, match.groups()[:2])) != (6, 4):
        raise ValueError(
            f'Lola Player CI requires Swift 6.4.x; found {match[0]}. '
            'Select Xcode 27.0 with DEVELOPER_DIR=/Applications/Xcode_27.app/Contents/Developer. '
            'Swift 6.3.3 crashed compiling PlayerView.swift in the v1.2.1 release run.')


def main():
    result = subprocess.run(['swift', '--version'], check=True, capture_output=True, text=True)
    output = result.stdout+result.stderr
    print(output.strip(), flush=True)
    try:
        validate(output)
    except ValueError as error:
        raise SystemExit(str(error)) from error
    print('Validated Swift 6.4 toolchain')


if __name__ == '__main__':
    main()
