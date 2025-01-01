package eventhandlers

import "github.com/github/go-stats"

// Skip is a struct that contains a reason for skipping an event handler.
type Skip struct {
	reason string
	tags   stats.Tags
}

// IsEmpty returns true if the Skip struct is empty.
func (s *Skip) IsEmpty() bool {
	return s.reason == "" && s.tags == nil
}

// Tags returns the tags for the skip.
func (s *Skip) Tags() stats.Tags {
	baseTags := stats.Tags{"success": "true", "skip": "true"}
	return baseTags.Merge(s.tags)
}
