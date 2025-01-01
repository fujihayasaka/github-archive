package types

type JobIDs []string

type RerunInfo struct {
	// WARNING! This struct is encoded/decoded as JSON and shared across a queue (`scheduled_builds`).
	// If you change the content of the struct, do so in a backward AND forward compatible manner!
	//
	// !!! See `(*workflowinvoker.Invocation).UnmarshalJSON()`

	PlanID string `json:"plan_id"`
	JobIDs JobIDs `json:"job_ids"`
}
