BASE=https://ezen.tysons.co.ke

# Struts action patterns
for a in landlord property propertyunit tenant \
         rental-invoices rent-receipts \
         meterreading propertyinspection \
         repairrequest workorder \
         accounts vendors customers invoices; do
  for ext in .action .do ""; do
    code=$(curl -s -o /dev/null -w '%{http_code}' -k "$BASE/$a$ext")
    echo "$code  /$a$ext"
  done
done
