package pbtypes

const (
	eventTypePush        = "push"
	eventTypePullRequest = "pull_request"
)

// ConfigString changes an EventType into its string form. The string form occurs in a flow file.
func (e EventType) ConfigString() (string, bool) {
	switch e {
	case EventType_PUSH:
		return eventTypePush, true
	case EventType_PULL_REQUEST:
		return eventTypePullRequest, true
	default:
		return "unknown", false
	}
}
