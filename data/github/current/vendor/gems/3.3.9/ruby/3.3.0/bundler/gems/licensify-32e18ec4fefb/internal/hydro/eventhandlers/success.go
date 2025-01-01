package eventhandlers

import "github.com/github/go-stats"

// Success is a struct that contains success details returned by an event handler.
type Success struct {
	tags stats.Tags
}

// Tags returns the tags for the success.
func (s *Success) Tags() stats.Tags {
	baseTags := stats.Tags{"success": "true", "skip": "false"}
	return baseTags.Merge(s.tags)
}
