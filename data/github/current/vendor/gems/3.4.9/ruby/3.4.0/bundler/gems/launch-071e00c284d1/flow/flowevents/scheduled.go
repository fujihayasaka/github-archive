package flowevents

// The JSON that referred to by GITHUB_EVENT_PATH for scheduled builds
type ScheduleEventPayload struct {
	Schedule     string         `json:"schedule"`
	Enterprise   map[string]any `json:"enterprise,omitempty"`
	Repository   map[string]any `json:"repository,omitempty"`
	Organization map[string]any `json:"organization,omitempty"`
	Workflow     string         `json:"workflow,omitempty"`
}

// passed to Action environment as GITHUB_EVENT_NAME
const ScheduleEventName = "schedule"

// ScheduleEvent is passed as a GitHubEvent
type ScheduleEvent struct{}
