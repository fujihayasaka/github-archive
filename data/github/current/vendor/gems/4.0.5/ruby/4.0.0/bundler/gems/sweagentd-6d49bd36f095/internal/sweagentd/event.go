package sweagentd

// Event represents an event, extending RepositoryWithActor to include agent ID access.
type Event interface {
	RepositoryWithActor

	GetAgentID() int64
}
