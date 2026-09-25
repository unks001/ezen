curl -s -k https://ezen.tysons.co.ke/login.js -o login.js
cat login.js

# also try common Struts login action names
for u in login.action login.do j_security_check \
         authenticate.action doLogin.action; do
  curl -i -k -o /dev/null -w "%{http_code}  $u\n" "https://ezen.tysons.co.ke/$u"
done
