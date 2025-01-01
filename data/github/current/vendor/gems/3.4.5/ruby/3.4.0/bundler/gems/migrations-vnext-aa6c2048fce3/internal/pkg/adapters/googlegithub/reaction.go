package googlegithub

import (
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"github.com/google/go-github/v65/github"
	"google.golang.org/protobuf/types/known/timestamppb"
)

// Reaction is a wrapper around the github.Reaction struct which allows us
// to implement our own methods.
type Reaction struct {
	github.Reaction
}

var timeNowFn = timestamppb.Now

// ToV1Reaction converts a github.Reaction to a v1.Reaction.
func (r Reaction) ToV1Reaction() (*v1.Reaction, error) {
	return &v1.Reaction{
		Content:        r.GetContent(),
		UserResourceId: r.GetUser().GetHTMLURL(),
		CreatedAt:      timeNowFn(),
	}, nil
}
