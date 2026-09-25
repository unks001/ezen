#!/usr/bin/env bash
# ezen-recon7.sh — read-only recon round 3
# Focus: /live context login, apikey/equityjengaapikey endpoints,
#        JS endpoint extraction, /run handler, store.js credential blocks.
#
# READ-ONLY: only list/load probes. No save. No writes.

set -u
BASE="https://ezen.tysons.co.ke"
UA="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36"
OUT="ezen-recon7-$(date +%Y%m%d-%H%M%S)"
DELAY=0.3

mkdir -p "$OUT" && cd "$OUT" || exit 1
C()  { curl -sS -L -k -A "$UA" -m 30 "$@"; }
CS() { sleep "$DELAY"; curl -sS -L -k -A "$UA" -m 30 "$@"; }
hr() { printf '\n===== %s =====\n' "$1"; }

# ------------------------------------------------------------------
hr "1. Login under /live context"

echo "--- GET /live/login?sal.tp=login ---"
CS -i "$BASE/live/login?sal.tp=login" -o live-login-get.txt
head -30 live-login-get.txt

echo
echo "--- POST /live/login?sal.tp=login (dummy creds) ---"
CS -i -X POST "$BASE/live/login?sal.tp=login" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data 'userAuthentication.username=test&userAuthentication.password=test' \
  -o live-login-post.txt
head -40 live-login-post.txt

echo
echo "--- other candidate login paths under /live ---"
for p in /live/login/login /live/login.action /live/j_security_check \
         /live/login.do /live/authenticate /live/index.jsp; do
  code=$(CS -o "/tmp/live_$(echo "$p" | tr '/' '_').out" -w '%{http_code}' "$BASE$p")
  echo "  $code  $p"
done

# ------------------------------------------------------------------
hr "2. apikey / equityjengaapikey endpoint discovery (READ-ONLY)"

for base in /live/api /live /api; do
  for r in apikey equityjengaapikey jengaapikey; do
    for sub in list load; do
      url="$BASE$base/$r/$sub"
      code=$(CS -o "/tmp/ak_$(echo "$base$r$sub" | tr '/' '_').json" -w '%{http_code}' "$url")
      size=$(wc -c < "/tmp/ak_$(echo "$base$r$sub" | tr '/' '_').json" 2>/dev/null || echo 0)
      printf '  %-4s %-7s %s\n' "$code" "$size" "$base/$r/$sub"
      if [ "$code" = "200" ] && [ "$size" -gt 30 ]; then
        echo "      >>> BODY <<<"
        head -c 800 "/tmp/ak_$(echo "$base$r$sub" | tr '/' '_').json"; echo
      fi
    done
  done
done

# save is only probed for existence via OPTIONS, never written
echo "--- OPTIONS only (no write) ---"
for base in /live/api /live /api; do
  for r in apikey equityjengaapikey jengaapikey; do
    code=$(CS -X OPTIONS -o /dev/null -w '%{http_code}' "$BASE$base/$r/save")
    echo "  OPTIONS $code  $base/$r/save"
  done
done

# ------------------------------------------------------------------
hr "3. Extract all url: references from JS files"

# Fetch any missing JS if not already present
for f in app/store.js app/property/property.js app/accounts/accounts.js app/hrm/hrm.js \
         app/ext-custom-cmp.js; do
  safe=$(echo "$f" | tr '/' '_')
  if [ ! -s "$safe" ]; then
    CS -o "$safe" "$BASE/$f"
  fi
done
ls -la *.js 2>/dev/null

echo "--- url: refs from each file ---"
for f in *.js; do
  echo "### $f"
  grep -oE "url: *'[^']+'" "$f" 2>/dev/null \
    | sed "s/url: *'//;s/'//" | sort -u
done | tee urls-by-file.txt

echo
echo "--- all unique urls across all js ---"
grep -hEo "url: *'[^']+'" *.js 2>/dev/null \
  | sed "s/url: *'//;s/'//" | sort -u > endpoints-from-js.txt
wc -l endpoints-from-js.txt
cat endpoints-from-js.txt

# also grab standalone quoted paths that look like endpoints
echo
echo "--- heuristic: quoted /path refs ---"
grep -hEo "'/[a-zA-Z0-9_./-]{2,}'" *.js 2>/dev/null \
  | tr -d "'" | sort -u >> endpoints-from-js.txt
sort -u endpoints-from-js.txt -o endpoints-from-js.txt
wc -l endpoints-from-js.txt

# ------------------------------------------------------------------
hr "4. store.js credential / model context"

for range in "6050,6300p" "9700,9850p" "10250,10350p"; do
  start=${range%,*}; end=${range%p}; end=${end#*,}
  fname="store-ctx-${start}-${end}.txt"
  sed -n "${start},${end}p" app_store.js > "$fname" 2>/dev/null
  echo "--- $fname ($(wc -l < "$fname") lines) ---"
  head -60 "$fname"
  echo "..."
  echo
done

echo "--- grep for secret-ish field names in store.js ---"
grep -nE "api_key|consumer_secret|consumer_key|apipassword|default_token|private_key|secret" \
  app_store.js | head -60 | tee store-secret-fields.txt

# ------------------------------------------------------------------
hr "5. /run handler body + headers"

echo "--- GET /run ---"
CS -i "$BASE/run" -o run-get.txt
head -40 run-get.txt

echo
echo "--- POST /run ---"
CS -i -X POST "$BASE/run" -o run-post.txt
head -40 run-post.txt

echo
echo "--- /run with json body ---"
CS -i -X POST "$BASE/run" -H 'Content-Type: application/json' -d '{}' -o run-post-json.txt
head -25 run-post-json.txt

echo
echo "--- /run body first 1000 bytes ---"
head -c 1000 run-get.txt

# ------------------------------------------------------------------
hr "6. Probe every endpoint discovered in JS (list/load only)"

if [ -s endpoints-from-js.txt ]; then
  : > js-probe-results.txt
  while IFS= read -r ep; do
    [ -z "$ep" ] && continue
    # normalize: strip leading slash for joining, skip full URLs
    case "$ep" in
      http*) url="$ep" ;;
      /*)    url="$BASE$ep" ;;
      *)     url="$BASE/live/$ep" ;;
    esac
    code=$(CS -o /tmp/ep_probe.json -w '%{http_code}' "$url")
    size=$(wc -c < /tmp/ep_probe.json 2>/dev/null || echo 0)
    if [ "$code" != "404" ] && [ "$code" != "000" ]; then
      printf '%s  %-7s %s\n' "$code" "$size" "$url" | tee -a js-probe-results.txt
      if [ "$code" = "200" ] && [ "$size" -gt 30 ]; then
        echo "     >>> $(head -c 300 /tmp/ep_probe.json)"
      fi
    fi
  done < endpoints-from-js.txt
else
  echo "[!] no endpoints extracted"
fi

# ------------------------------------------------------------------
hr "7. Re-confirm banks list bounds + count"

CS -o banks-full.json "$BASE/live/api/banks/list?start=0&limit=100000"
if command -v jq >/dev/null; then
  echo "count: $(jq -r '.count' banks-full.json)"
  echo "list len: $(jq -r '.list|length' banks-full.json)"
fi

# ------------------------------------------------------------------
hr "SUMMARY"
echo "Output dir: $(pwd)"
ls -la
echo
echo "Artifacts:"
echo "  live-login-get.txt / live-login-post.txt   — /live login attempts"
echo "  endpoints-from-js.txt                      — all JS-derived endpoints"
echo "  urls-by-file.txt                           — per-file url refs"
echo "  store-ctx-*.txt                            — store.js context blocks"
echo "  store-secret-fields.txt                    — secret field names"
echo "  run-get.txt / run-post.txt                 — /run handler output"
echo "  js-probe-results.txt                       — non-404 hits from JS map"
echo
echo "CRITICAL: if any apikey/list or equityjengaapikey/list returned 200"
echo "with real credential data, STOP and report immediately."
