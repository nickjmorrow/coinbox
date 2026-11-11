#!/bin/sh
# Fills a scratch database with a small invented budget, to look at the apps. Usage: scripts/seed-demo.sh /tmp/coinbox-demo.sqlite
set -e
db="${1:?usage: seed-demo.sh <database file>}"
rm -f "$db" "$db-wal" "$db-shm"
cb="$(cd "$(dirname "$0")/.." && pwd)/CLI/.build/release/coinbox"
c() { "$cb" "$@" --db "$db" >/dev/null; }
month="${MONTH:-$(date +%Y-%m)}"
prev="$(date -v-1m +%Y-%m)"
c account put --json '{"id":"chk","name":"Checking","kind":"checking"}'
c account put --json '{"id":"sav","name":"Savings","kind":"savings"}'
c account put --json '{"id":"visa","name":"Visa","kind":"creditCard"}'
c account put --json '{"id":"mort","name":"Mortgage","kind":"mortgage"}'
c category-group put --json '{"id":"bills","name":"Bills","order":1}'
c category-group put --json '{"id":"life","name":"Everyday","order":2}'
for row in "rent:bills:Rent" "power:bills:Electric" "groc:life:Groceries" "eat:life:Eating out" "fun:life:Fun"; do
  id="${row%%:*}"; rest="${row#*:}"; g="${rest%%:*}"; n="${rest#*:}"
  c category put --json "{\"id\":\"$id\",\"groupID\":\"$g\",\"name\":\"$n\"}"
done
c target put --json '{"categoryID":"rent","amount":1400000,"cadence":{"type":"monthly","day":1}}'
c target put --json '{"categoryID":"power","amount":90000,"cadence":{"type":"monthly","day":15}}'
c target put --json '{"categoryID":"groc","amount":150000,"cadence":{"type":"weekly","isoWeekday":6}}'
c transaction put --json "{\"id\":\"i1\",\"accountID\":\"chk\",\"date\":\"$prev-01\",\"amount\":4200000,\"categoryID\":\"ready-to-assign\",\"cleared\":\"reconciled\",\"rawPayee\":\"PAYROLL\"}"
c transaction put --json "{\"id\":\"i2\",\"accountID\":\"chk\",\"date\":\"$month-01\",\"amount\":4200000,\"categoryID\":\"ready-to-assign\",\"cleared\":\"cleared\",\"rawPayee\":\"PAYROLL\"}"
c transaction put --json "{\"id\":\"s1\",\"accountID\":\"sav\",\"date\":\"$prev-01\",\"amount\":2500000,\"categoryID\":\"ready-to-assign\",\"cleared\":\"reconciled\"}"
c transaction put --json "{\"id\":\"v0\",\"accountID\":\"visa\",\"date\":\"$prev-01\",\"amount\":-600000,\"cleared\":\"reconciled\",\"memo\":\"Starting Balance\"}"
c assign rent "$prev" 1400 ; c assign power "$prev" 90 ; c assign groc "$prev" 600 ; c assign fun "$prev" 200 ; c assign eat "$prev" 150
c assign rent "$month" 1400 ; c assign groc "$month" 300 ; c assign power "$month" 40
c transaction put --json "{\"id\":\"r1\",\"accountID\":\"chk\",\"date\":\"$month-01\",\"amount\":-1400000,\"categoryID\":\"rent\",\"cleared\":\"cleared\",\"rawPayee\":\"LANDLORD LLC\"}"
c transaction put --json "{\"id\":\"g1\",\"accountID\":\"visa\",\"date\":\"$month-03\",\"amount\":-86400,\"categoryID\":\"groc\",\"cleared\":\"cleared\",\"rawPayee\":\"TRADER JOES #4\"}"
c transaction put --json "{\"id\":\"g2\",\"accountID\":\"chk\",\"date\":\"$month-04\",\"amount\":-23150,\"categoryID\":\"groc\",\"cleared\":\"cleared\",\"rawPayee\":\"CORNER MARKET\"}"
c transaction put --json "{\"id\":\"e1\",\"accountID\":\"visa\",\"date\":\"$month-05\",\"amount\":-61000,\"categoryID\":\"eat\",\"cleared\":\"uncleared\",\"approved\":false,\"rawPayee\":\"SUSHI PLACE\"}"
c transaction put --json "{\"id\":\"u1\",\"accountID\":\"chk\",\"date\":\"$month-06\",\"amount\":-5400,\"approved\":false,\"rawPayee\":\"STARBUCKS #1182\"}"
c transaction put --json "{\"id\":\"u2\",\"accountID\":\"chk\",\"date\":\"$month-06\",\"amount\":-71200,\"approved\":false,\"rawPayee\":\"CITY POWER AND LIGHT\"}"
c rule put-many --json '[{"id":"ru1","name":"Coffee","payee":{"mode":"contains","text":"starbucks"},"actions":{"renamePayee":"Starbucks","categoryID":"eat","approve":true}},{"id":"ru2","name":"Electric","payee":{"mode":"contains","text":"power and light"},"actions":{"renamePayee":"City Power","categoryID":"power"}}]'
echo "seeded $db"
