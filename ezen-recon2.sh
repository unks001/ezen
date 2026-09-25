BASE=https://ezen.tysons.co.ke/live/api

# list
curl -i -k "$BASE/banks/list"

# load with a few IDs
for id in 1 2 3 0 -1 admin; do
  echo "--- id=$id ---"
  curl -i -k "$BASE/banks/load/$id"
done

# save — POST, try empty and JSON bodies
curl -i -k -X POST "$BASE/banks/save" \
  -H 'Content-Type: application/json' -d '{}'

curl -i -k -X POST "$BASE/banks/save" \
  -H 'Content-Type: application/json' \
  -d '{"id":1,"name":"test"}'
