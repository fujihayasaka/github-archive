package migrations

var _ = Transitions.Step(1000).Simple(`UPDATE ts_analyses SET sarif_url = "" WHERE sarif_url is NULL LIMIT ?`)
