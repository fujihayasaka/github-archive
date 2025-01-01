package archive

import (
	"testing"

	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"github.com/stretchr/testify/assert"
)

func TestPrepareReactionBatches(t *testing.T) {
	testCases := []struct {
		name            string
		reactions       []*v1.Reaction
		subjectID       string
		batchSize       int
		expectedBatches int
		expectError     bool
	}{
		{
			name:            "Normal case, multiple batches",
			reactions:       []*v1.Reaction{{}, {}, {}, {}, {}},
			subjectID:       "subject",
			batchSize:       2,
			expectedBatches: 3, // 5 reactions, 2 per batch = 3 batches
		},
		{
			name:            "Empty reactions list",
			reactions:       []*v1.Reaction{},
			subjectID:       "subject",
			batchSize:       2,
			expectedBatches: 0,
		},
		{
			name:            "Batch size larger than reactions",
			reactions:       []*v1.Reaction{{}, {}},
			subjectID:       "subject",
			batchSize:       10,
			expectedBatches: 1, // All reactions in one batch
		},
		{
			name:            "Invalid batch size (zero)",
			reactions:       []*v1.Reaction{{}, {}},
			subjectID:       "subject",
			batchSize:       0,
			expectedBatches: 0,
		},
		{
			name:            "Exact batch size",
			reactions:       []*v1.Reaction{{}, {}, {}},
			subjectID:       "subject",
			batchSize:       3,
			expectedBatches: 1, // 3 reactions, 3 per batch = 1 batch
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			batches := prepareReactionsBatches(tc.reactions, tc.subjectID, v1.ReactionSubjectType_REACTION_SUBJECT_TYPE_ISSUE, tc.batchSize)
			assert.Equal(t, tc.expectedBatches, len(batches))
			for _, b := range batches {
				assert.Contains(t, b.ResourceId, tc.subjectID)
			}
		})
	}
}
