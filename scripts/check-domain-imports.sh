#!/usr/bin/env bash
# T-2.4 / DW-2.1: static check that the Domain layer imports none of
# EventKit/UIKit/networking (or other UI/extension frameworks). Domain must
# stay pure so agenda/filter logic runs against fakes with no I/O.
#
# This is the fast standalone CI gate; the same rule is also enforced in the
# unit suite by DomainImportBoundaryTests (which runs inside `make test`).
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
domain_dir="$repo_root/CalenminderKit/Domain"

if [[ ! -d "$domain_dir" ]]; then
  echo "error: Domain directory not found at $domain_dir" >&2
  exit 2
fi

# Word-boundary match on real import declarations (allows @testable/@_exported).
forbidden='EventKit|UIKit|AppKit|WidgetKit|SwiftUI|AppIntents|Network'
pattern="^[[:space:]]*(@[[:alnum:]_]+[[:space:]]+)*import[[:space:]]+(${forbidden})([[:space:]]|\.|$)"

if grep -REn "$pattern" "$domain_dir" --include='*.swift'; then
  echo "error: forbidden import found in Domain (see lines above)" >&2
  exit 1
fi

echo "ok: Domain imports are clean (no EventKit/UIKit/networking)"
