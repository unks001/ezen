#!/usr/bin/env bash
# ezen-recon.sh — follow-up recon for ezen.tysons.co.ke
# Usage: ./ezen-recon.sh [base_url]
# Default base: http://ezen.tysons.co.ke

set -u
BASE="${1:-https://ezen.tysons.co.ke}"
OUT="ezen-recon-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"
cd "$OUT" || exit 1

UA="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36"
CURL=(curl -sS -L -k -A "$UA" -m 30)

hr(){ printf '\n===== %s =====\n' "$1"; }

# ---------- 1. Swagger / API spec ----------
hr "1. Swagger spec"
"${CURL[@]}" -o swagger.json -w "swagger.json  HTTP:%{http_code}  size:%{size_download}\n" \
  "$BASE/api/swagger.json"

if command -v jq >/dev/null && [ -s swagger.json ]; then
  echo "--- host / basePath / schemes ---"
  jq -r '[.host, .basePath, (.schemes|join(","))] | @tsv' swagger.json 2>/dev/null
  echo "--- endpoints ---"
  jq -r '.paths | keys[]' swagger.json 2>/dev/null | tee endpoints.txt
  echo "--- methods per endpoint ---"
  jq -r '.paths | to_entries[] | "\(.key)\t\(.value|keys|join(","))"' swagger.json 2>/dev/null \
    | tee endpoints-methods.txt
  echo "--- security schemes ---"
  jq -r '.securityDefinitions // .components.securitySchemes // {} | keys[]' swagger.json 2>/dev/null
else
  echo "[!] jq not installed or empty spec — install jq: sudo apt install jq"
fi

hr "1b. /apidocs page"
"${CURL[@]}" -o apidocs.html -w "apidocs.html  HTTP:%{http_code}  size:%{size_download}\n" \
  "$BASE/apidocs"
grep -oiE '(src|href)="[^"]+"' apidocs.html 2>/dev/null | head -40

# ---------- 2. app.js ----------
hr "2. app.js"
"${CURL[@]}" -o app.js -w "app.js  HTTP:%{http_code}  size:%{size_download}\n" \
  "$BASE/app.js"

if [ -s app.js ]; then
  echo "--- candidate paths in app.js ---"
  grep -oE '"/[a-zA-Z0-9_/.-]{2,}"' app.js | tr -d '"' | sort -u | tee appjs-paths.txt
  echo "--- possible secrets ---"
  grep -inE 'api[_-]?key|token|secret|passw|authorization|bearer|aws_|firebase' app.js \
    | head -30 | tee appjs-secrets.txt
fi

# ---------- 3. login surfaces ----------
hr "3. Login surfaces"
"${CURL[@]}" -o login.html -w "login.html  HTTP:%{http_code}  size:%{size_download}\n" \
  "$BASE/login.html"
echo "--- login.html form/action refs ---"
grep -oiE '<form[^>]*>|action="[^"]+"|(src|href)="[^"]+"' login.html 2>/dev/null | head -30

echo "--- POST /login/login ---"
"${CURL[@]}" -o login-login.out -w "login/login  HTTP:%{http_code}  size:%{size_download}\n" \
  -X POST "$BASE/login/login" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data 'username=test&password=test'
head -c 400 login-login.out; echo

echo "--- GET /api/swagger (403 baseline) ---"
"${CURL[@]}" -o /dev/null -w "api/swagger  HTTP:%{http_code}\n" "$BASE/api/swagger"

# ---------- 4. 8KB group: download / output / run ----------
hr "4. 8KB endpoints (download / output / run)"
for p in download output run; do
  "${CURL[@]}" -o "$p.out" -w "$p  HTTP:%{http_code}  size:%{size_download}\n" "$BASE/$p"
  printf '  md5: '; md5sum "$p.out" | awk '{print $1}'
  printf '  title: '; grep -oiE '<title>[^<]*</title>' "$p.out" | head -1
  printf '  first line: '; head -1 "$p.out" | cut -c1-100
  echo
done

echo "--- also try POST on each ---"
for p in download output run; do
  code=$("${CURL[@]}" -o "/tmp/$p.post" -w '%{http_code}' -X POST "$BASE/$p")
  echo "POST /$p -> $code  (size: $(wc -c < /tmp/$p.post))"
done

# ---------- 5. 18KB group: confirm SPA fallback ----------
hr "5. 18KB group — SPA fallback check"
declare -a PATHS=(
  "/"
  "/index.html"
  "/%3f/"
  "/;/admin"
  "/;/json"
  "/;/login"
  "/;admin/"
  "/;json/"
  "/;login/"
  "/this-does-not-exist-9f3a2b"
)
for p in "${PATHS[@]}"; do
  body=$("${CURL[@]}" "$BASE$p")
  sz=$(printf '%s' "$body" | wc -c)
  md5=$(printf '%s' "$body" | md5sum | awk '{print $1}')
  printf '%-28s size:%-7s md5:%s\n' "$p" "$sz" "$md5"
done
echo
echo "If all md5s above match -> confirmed SPA fallback (no real bypass)."

# ---------- summary ----------
hr "SUMMARY"
echo "Output dir: $(pwd)"
ls -la
echo
echo "Key files:"
echo "  swagger.json           — API spec"
echo "  endpoints.txt          — API paths (if jq present)"
echo "  endpoints-methods.txt  — paths + HTTP methods"
echo "  apidocs.html           — API docs page"
echo "  app.js                 — client JS"
echo "  appjs-paths.txt        — paths found in app.js"
echo "  appjs-secrets.txt      — possible secrets in app.js"
echo "  login.html             — standalone login page"
echo "  login-login.out        — response from POST /login/login"
echo "  {download,output,run}.out — 8KB endpoint bodies"
