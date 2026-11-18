#!/usr/bin/env bash
# Entry point of the shared release kit; see Scripts/release/README.md.
exec bash "$(dirname "$0")/release/install.sh" "$@"
