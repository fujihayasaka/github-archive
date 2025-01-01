package ts

type CodeqlRunTriggeringEvent uint8

const (
	CodeqlRunTriggeringEvent_VALIDATION CodeqlRunTriggeringEvent = iota
	CodeqlRunTriggeringEvent_PUSH
	CodeqlRunTriggeringEvent_PULL_REQUEST
	CodeqlRunTriggeringEvent_UNKNOWN
	CodeqlRunTriggeringEvent_SCHEDULED
	CodeqlRunTriggeringEvent_LANGUAGES_CHANGE
)

func (e CodeqlRunTriggeringEvent) String() string {
	var event string

	switch e {
	case CodeqlRunTriggeringEvent_VALIDATION:
		event = "Validation Run"
	case CodeqlRunTriggeringEvent_PUSH:
		event = "Push"
	case CodeqlRunTriggeringEvent_PULL_REQUEST:
		event = "Pull Request"
	case CodeqlRunTriggeringEvent_UNKNOWN:
		event = "Unknown"
	case CodeqlRunTriggeringEvent_SCHEDULED:
		event = "Scheduled"
	case CodeqlRunTriggeringEvent_LANGUAGES_CHANGE:
		event = "Languages Change"
	}

	return event
}
