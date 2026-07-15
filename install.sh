#!/usr/bin/env bash
# GamePanel root installer entrypoint
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "${ROOT}/installer/install.sh" "$@"
