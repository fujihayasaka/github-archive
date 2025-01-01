package layout

import (
	"testing"

	"github.com/stretchr/testify/require"

	schemas_pb "github.com/github/notifyd/hydro/schemas/notifyd/v0"
	entities_pb "github.com/github/notifyd/hydro/schemas/notifyd/v0/entities"
)

func TestGetReasonAndType(t *testing.T) {
	r := require.New(t)

	tests := []struct {
		name           string
		reasons        []string
		expectedReason string
		expectedType   string
	}{
		{
			name:           "No reasons",
			reasons:        []string{},
			expectedReason: "",
			expectedType:   "",
		},
		{
			name:           "Single reason",
			reasons:        []string{"mention"},
			expectedReason: "mention",
			expectedType:   "mention",
		},
		{
			name:           "Other reason",
			reasons:        []string{"assign"},
			expectedReason: "assign",
			expectedType:   "assigned",
		},
		{
			name:           "Multiple reasons",
			reasons:        []string{"assign", "mention", "review_requested"},
			expectedReason: "mention",
			expectedType:   "mention",
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			msg := Message{&schemas_pb.DeliverMobilePush{
				Reasons: make([]*entities_pb.Reason, len(test.reasons)),
			}}

			for i, reason := range test.reasons {
				msg.Reasons[i] = &entities_pb.Reason{Name: reason}
			}

			reason, notificationType := msg.GetReasonAndType()

			r.Equal(test.expectedReason, reason)
			r.Equal(test.expectedType, notificationType)
		})
	}
}
