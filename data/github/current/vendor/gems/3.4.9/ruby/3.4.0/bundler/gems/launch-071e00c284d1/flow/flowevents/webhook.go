package flowevents

import (
	"github.com/google/go-github/v25/github"
)

func ParseEventWebHook(event string, payload []byte) (GitHubEvent, error) {
	// Wrap the call to ParseWebHook() so we can use GitHubEvent as the return type instead of interface{}
	// No longer needed if https://github.com/google/go-github/issues/2462 is implemented
	return github.ParseWebHook(event, payload)
}
