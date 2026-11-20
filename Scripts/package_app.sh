#!/usr/bin/env bash
# Entry point of the shared packager; app facts live in release.env (see Scripts/release/README.md).
exec bash "$(dirname "$0")/release/package.sh" "$@"
