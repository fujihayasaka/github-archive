package migrations

var _ = Transitions.Batched("ts_codeql_repos", "UPDATE ts_codeql_repos FORCE INDEX(PRIMARY) SET runner_label = 'code-scanning' WHERE using_cs_runner_label AND runner_label IS NULL AND id BETWEEN ? AND ?")
