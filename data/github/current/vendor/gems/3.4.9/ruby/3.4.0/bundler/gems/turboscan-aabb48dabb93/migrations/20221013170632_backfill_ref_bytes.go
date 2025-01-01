package migrations

var _ = Transitions.Batched("ts_analyses", `UPDATE ts_analyses FORCE INDEX(PRIMARY) SET ref_bytes = ref WHERE id BETWEEN ? AND ?`)
