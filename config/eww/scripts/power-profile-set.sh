#!/usr/bin/env bash
# Set the active power profile via powerprofilesctl. The popup re-reads
# state on the next tick (5s) so no explicit refresh is needed.
# Usage: power-profile-set.sh power-saver|balanced|performance

set -euo pipefail
powerprofilesctl set "${1:?missing profile name}"
