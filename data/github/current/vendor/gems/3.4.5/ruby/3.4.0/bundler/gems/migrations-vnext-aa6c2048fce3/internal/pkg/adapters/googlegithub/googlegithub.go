// Package googlegithub provides logic for converting structs from the
// google/go-github library to our domain models.
package googlegithub

import (
	"github.com/google/go-github/v65/github"
	"google.golang.org/protobuf/types/known/timestamppb"
)

// toTimestamp is a helper function for converting a github.Timestamp
// to a timestamppb.Timestamp for use within a protobuf message.
func toTimestamp(t *github.Timestamp) *timestamppb.Timestamp {
	if t == nil || t.GetTime() == nil || t.GetTime().IsZero() {
		return nil
	}
	return timestamppb.New(*t.GetTime())
}
