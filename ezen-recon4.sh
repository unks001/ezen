for p in landlord property propertyunit tenant \
         propertyreports agedanalysis slipcollection \
         rental-invoices rent-receipts \
         metereadingcat metereadingconfig meterreading \
         propertyinspection inspectioncategory inspectioncondition \
         repairrequest workorderservicecat workorder \
         accounts acctxnclass productservice clientcategory \
         vendors customers invoices; do
  code=$(curl -s -o /dev/null -w '%{http_code}' -k "$BASE/ajax/$p.html")
  echo "$code  /ajax/$p.html"
done
