package migrations

var _ = Transitions.Batched("ts_codeql_runs", `UPDATE ts_codeql_runs FORCE INDEX(PRIMARY) SET ref_bytes = ref WHERE id BETWEEN ? AND ? AND ref_bytes IS NULL`)
