package googlegithub

import (
	"testing"
	"time"

	"github.com/google/go-github/v65/github"
	"github.com/stretchr/testify/assert"
	"google.golang.org/protobuf/types/known/timestamppb"
)

func Test_toTimestamp(t *testing.T) {
	tests := map[string]struct {
		gets  *github.Timestamp
		wants *timestamppb.Timestamp
	}{
		"should return nil when the input in nil": {
			gets:  nil,
			wants: nil,
		},
		"should return nil if GetTime returns zero": {
			gets:  &github.Timestamp{Time: time.Date(0o001, 1, 1, 0o0, 0o0, 0o0, 0o0, time.UTC)},
			wants: nil,
		},
		"should return the converted timestamp when valid input is provided": {
			gets:  &github.Timestamp{Time: time.Date(2024, 1, 1, 0o0, 0o0, 0o0, 0o0, time.UTC)},
			wants: timestamppb.New(time.Date(2024, 1, 1, 0o0, 0o0, 0o0, 0o0, time.UTC)),
		},
	}

	for name, test := range tests {
		t.Run(name, func(t *testing.T) {
			assert.Equal(t, test.wants, toTimestamp(test.gets))
		})
	}
}
