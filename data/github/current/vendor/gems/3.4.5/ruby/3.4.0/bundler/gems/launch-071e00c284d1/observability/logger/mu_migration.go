package logger

// DefaultFieldTags are fields that will always be sent to Sentry
var DefaultFieldTags = map[string]bool{
	"gh.launch.service.name":         true,
	"gh.repo.global_id":              true,
	"gh.request_id":                  true,
	"gh.launch.event.name":           true,
	"gh.launch.synthetic_event.name": true,
}
