#!/usr/bin/env bash
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CM="$ROOT/local/bin/cm-singbox"
PY="$ROOT/win/singbox.py"

TAG="testtag"

CASES=(
  "vless://aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee@example.com:443#Paris"
  "vless://aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee@example.com:443"
  "vless://aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee@example.com:443?flow=xtls-rprx-vision#Fast"
  "vless://aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee@example.com:443?security=reality&pbk=abc123&sid=01&fp=chrome&sni=booking.com&flow=xtls-rprx-vision#Paris%20Reality"
  "vless://aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee@example.com:8443?security=reality&pbk=pubkey#NoSid"
  "vless://aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee@example.com:443?security=tls&sni=example.com&fp=firefox#TlsNoReality"
  "vless://aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee@example.com:443?security=tls#TlsOnly"
  "vless://aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee@example.com:443?flow=xtls-rprx-vision"
  "not-valid"
  "vless://uuid-with-no-at-sign:443#broken"
  "vless://aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee@example.com#NowherePort"
)

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# bash side: extract urldecode + parse_vless by sourcing the script.
source "$CM"

i=0
for c in "${CASES[@]}"; do
  out=$(parse_vless "$c" "$TAG" 2>/dev/null)
  if [[ -z "$out" ]]; then echo "null"; else echo "$out"; fi
done > "$tmp/bash.out"

# python side: import the Windows module and call parse_vless.
python3 - "$PY" "$tmp/py.out" ${CASES[@]} <<'EOF'
import sys, json, importlib.util
py, out_path = sys.argv[1], sys.argv[2]
cases = sys.argv[3:]
spec = importlib.util.spec_from_file_location("singbox", py)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
out = []
for line in cases:
    r = m.parse_vless(line, "testtag")
    out.append("null" if r is None else json.dumps(r))
open(out_path, "w").write("\n".join(out) + "\n")
EOF

# Canonicalize both (sorted keys) and compare.
jq -S . "$tmp/bash.out" > "$tmp/bash.canon"
jq -S . "$tmp/py.out"   > "$tmp/py.canon"

if diff -u "$tmp/py.canon" "$tmp/bash.canon"; then
  echo "PARITY OK: bash and python emit identical output for all ${#CASES[@]} cases"
else
  echo "PARITY FAIL" >&2
  exit 1
fi