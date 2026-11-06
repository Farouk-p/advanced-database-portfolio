#!/usr/bin/env bash
# Usage: ./run_plans.sh before   (or: after)
# Runs every query in 01_queries.sql under EXPLAIN (ANALYZE, BUFFERS) and saves the plans.
set -e
label=${1:?usage: ./run_plans.sh before|after}
out=evidence/plans_${label}.txt
python3 - "$out" <<'PY'
import re, subprocess, sys
out = sys.argv[1]
open(out, "w").close()
queries = [q for q in open("01_queries.sql").read().split(";") if re.search(r"SELECT", q)]
for i, q in enumerate(queries, 1):
    q = q.strip()
    sql = "EXPLAIN (ANALYZE, BUFFERS) " + re.sub(r"^(--.*\n)+", "", q) + ";"
    r = subprocess.run(["docker", "exec", "-i", "farpoint-pg", "psql", "-U", "kobo", "-d", "farpoint"],
                       input=sql, text=True, capture_output=True)
    open(out, "a").write(f"===== Q{i} =====\n{q};\n\n{r.stdout}{r.stderr}\n")
PY
grep -E "^===== |Execution Time" "$out"
