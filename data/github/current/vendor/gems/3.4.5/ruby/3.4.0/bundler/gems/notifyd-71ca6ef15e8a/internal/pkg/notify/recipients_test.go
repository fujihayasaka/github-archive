package notify

import (
	"testing"

	"github.com/stretchr/testify/require"

	schema_pb "github.com/github/notifyd/hydro/schemas/notifyd/v0"
)

func Test_Batcher(t *testing.T) {
	r := require.New(t)
	recipients := RecipientIDToReasons{
		1: []string{"mention", "assign"},
		2: []string{"assign"},
		3: []string{"mention"},
	}

	tests := []struct {
		name       string
		batcher    Batcher
		partitions int
		size       uint
	}{
		{
			name:       "a batcher with batch size of 0",
			size:       0,
			partitions: 1,
		},
		{
			name:       "a batcher with batch size of 1 (even partitions)",
			size:       1,
			partitions: 3,
		},
		{
			name:       "a batcher with batch size of 2 (uneven partitions)",
			size:       2,
			partitions: 2,
		},
		{
			name:       "a batcher with batch size of 3 (single partition)",
			size:       3,
			partitions: 1,
		},
		{
			name:       "a batcher with batch size of 4 (single partition, bigger than whole set)",
			size:       4,
			partitions: 1,
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			b := Batcher{test.size}
			partitions := b.Split(recipients)

			r.Len(partitions, test.partitions)
			for _, partition := range partitions {
				if test.size == 0 {
					r.Len(partition, len(recipients))
				} else {
					r.LessOrEqual(len(partition), int(test.size))
				}
			}
		})
	}
}

func Test_RecipientIDToReasons_ToPB(t *testing.T) {
	r := require.New(t)

	tests := []struct {
		name                 string
		recipientIDToReasons RecipientIDToReasons
		expectedPBRecipients []*schema_pb.Notify_RecipientGroup
	}{
		{
			name: "converts a single recipient with a single reason",
			recipientIDToReasons: RecipientIDToReasons{
				1: []string{"mention"},
			},
			expectedPBRecipients: []*schema_pb.Notify_RecipientGroup{
				{
					UserIds: []int32{1},
					Reason:  "mention",
				},
			},
		},
		{
			name: "converts a single recipient with a multiple reasons",
			recipientIDToReasons: RecipientIDToReasons{
				1: []string{"mention", "subscribed"},
			},
			expectedPBRecipients: []*schema_pb.Notify_RecipientGroup{
				{
					UserIds: []int32{1},
					Reason:  "mention",
				},
				{
					UserIds: []int32{1},
					Reason:  "subscribed",
				},
			},
		},
		{
			name: "converts multiple recipient with a single reason",
			recipientIDToReasons: RecipientIDToReasons{
				1: []string{"mention"},
				2: []string{"mention"},
			},
			expectedPBRecipients: []*schema_pb.Notify_RecipientGroup{
				{
					UserIds: []int32{1, 2},
					Reason:  "mention",
				},
			},
		},
		{
			name: "converts multiple recipient with a multiple reasons",
			recipientIDToReasons: RecipientIDToReasons{
				1: []string{"mention", "subscribed"},
				2: []string{"mention", "subscribed"},
			},
			expectedPBRecipients: []*schema_pb.Notify_RecipientGroup{
				{
					UserIds: []int32{1, 2},
					Reason:  "mention",
				},
				{
					UserIds: []int32{1, 2},
					Reason:  "subscribed",
				},
			},
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			actualPBRecipients := test.recipientIDToReasons.ToPB()
			r.Len(actualPBRecipients, len(test.expectedPBRecipients))
		})
	}
}

func Test_PB_ToRecipientIDToReasons(t *testing.T) {
	r := require.New(t)

	tests := []struct {
		name                         string
		pbRecipients                 []*schema_pb.Notify_RecipientGroup
		expectedRecipientIDToReasons RecipientIDToReasons
	}{
		{
			name: "converts a single recipient with a single reason",
			pbRecipients: []*schema_pb.Notify_RecipientGroup{
				{
					UserIds: []int32{1},
					Reason:  "mention",
				},
			},
			expectedRecipientIDToReasons: RecipientIDToReasons{
				1: []string{"mention"},
			},
		},

		{
			name: "converts a single recipient with a multiple reasons",
			expectedRecipientIDToReasons: RecipientIDToReasons{
				1: []string{"mention", "subscribed"},
			},
			pbRecipients: []*schema_pb.Notify_RecipientGroup{
				{
					UserIds: []int32{1},
					Reason:  "mention",
				},
				{
					UserIds: []int32{1},
					Reason:  "subscribed",
				},
			},
		},
		{
			name: "converts multiple recipient with a single reason",
			expectedRecipientIDToReasons: RecipientIDToReasons{
				1: []string{"mention"},
				2: []string{"mention"},
			},
			pbRecipients: []*schema_pb.Notify_RecipientGroup{
				{
					UserIds: []int32{1, 2},
					Reason:  "mention",
				},
			},
		},
		{
			name: "converts multiple recipient with a multiple reasons",
			expectedRecipientIDToReasons: RecipientIDToReasons{
				1: []string{"mention", "subscribed"},
				2: []string{"mention", "subscribed"},
			},
			pbRecipients: []*schema_pb.Notify_RecipientGroup{
				{
					UserIds: []int32{1, 2},
					Reason:  "mention",
				},
				{
					UserIds: []int32{1, 2},
					Reason:  "subscribed",
				},
			},
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			var explicitRecipients ExplicitRecipients = test.pbRecipients
			actualRecipientIDToReasons := explicitRecipients.ToRecipientIDToReasons()

			r.Len(actualRecipientIDToReasons, len(test.expectedRecipientIDToReasons))
		})
	}
}
