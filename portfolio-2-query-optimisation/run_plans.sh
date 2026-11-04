#!/usr/bin/env bash
# Usage: ./run_plans.sh before|after   -> writes evidence/plans_<label>.txt
set -e
label=${1:?before|after}
out=evidence/plans_${label}.txt; : > "$out"
python3 - "$out" <<'PY'
import re,subprocess,sys
out=sys.argv[1]
qs=[q.strip() for q in open('01_queries.sql').read().split(';') if re.search(r'SELECT|WITH',q)]
for i,q in enumerate(qs,1):
    q=re.sub(r'^(\s*--.*\n)+','',q.strip()+'\n').strip()
    sql=f"EXPLAIN (ANALYZE, BUFFERS) {q};"
    r=subprocess.run(['docker','exec','-i','naijamart-pg','psql','-U','naija','-d','naijamart'],input=sql,text=True,capture_output=True)
    open(out,'a').write(f"===== Q{i} =====\n{q}\n\n{r.stdout}{r.stderr}\n")
PY
grep -E "^===== |Execution Time" "$out"
