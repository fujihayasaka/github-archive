package logkeys

// StageName is a high level step in an operation
type StageName string

const (
	// InvokerStart is at the beginning of a Start call
	InvokerStartStage StageName = "workflowinvoker.Start"
	// InvocationResolve occurs when we've loaded enough to know which commit will be built (not the event commit for PRs)
	InvocationResolvedStage StageName = "workflowinvoker.Start.resolved"

	// ExchangeURL occurs at the start of artifactsexchange's ExchangeURL
	ExchangeURLStage StageName = "artifactsexchange.ExchangeURL"
)
