# Fetch the XHR doc pages to extract exact action names/params
for p in repairrequest slipcollection employee announcement metereading propertyinspection; do
  curl -sk -H "X-Requested-With: XMLHttpRequest" \
    "https://ezen.tysons.co.ke/ajax/${p}.html" -o "${p}.doc"
done
# grep for file params / accept attributes
grep -iE "file|upload|enctype|accept=|multipart" *.doc
