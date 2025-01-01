package migrations

var _ = Transitions.Batched("ts_codeql_configs", "UPDATE ts_codeql_configs FORCE INDEX(PRIMARY) SET runner_label = 'code-scanning' WHERE using_cs_runner_label AND runner_label IS NULL AND id BETWEEN ? AND ?")
