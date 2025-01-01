package archive

import (
	"fmt"
	"time"

	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"github.com/google/uuid"
)

// Reactions represent a list of reactions.
type Reactions []Reaction

// Reaction represents a reaction to a subject.
type Reaction struct {
	CreatedAt   time.Time `json:"created_at"`
	Content     string    `json:"content"`
	SubjectType string    `json:"subject_type"`

	// User is the URL to the user's profile.
	User string `json:"user"`
}

// prepareReactionBatches takes a list of reactions and returns multiple batches enforcing a max batch size
// for the underlying reactions resource. A batchSize greater than zero is required.
func prepareReactionsBatches(reactions []*v1.Reaction, subjectResourceID string, subjectType v1.ReactionSubjectType, batchSize int) []*v1.ReactionsBatch {
	if batchSize <= 0 {
		return []*v1.ReactionsBatch{}
	}
	batches := []*v1.ReactionsBatch{}
	currentBatch := &v1.ReactionsBatch{}
	addBatch := func() {
		if len(currentBatch.Reactions) == 0 {
			return
		}
		currentBatch.SubjectResourceId = subjectResourceID
		currentBatch.SubjectType = subjectType
		currentBatch.ResourceId = fmt.Sprintf("reactions-%s-%s", subjectResourceID, uuid.New().String())
		batches = append(batches, currentBatch)
		currentBatch = &v1.ReactionsBatch{}
	}
	for _, r := range reactions {
		currentBatch.Reactions = append(currentBatch.Reactions, r)
		if len(currentBatch.Reactions) >= batchSize {
			addBatch()
		}
	}

	// add any remaining items to a new batch.
	addBatch()

	return batches
}

// ExtractV1Reactions converts Reactions to a list of v1.Reaction.
func (r Reactions) ExtractV1Reactions() []*v1.Reaction {
	var v1Reactions []*v1.Reaction
	for _, reaction := range r {
		v1Reactions = append(v1Reactions, &v1.Reaction{
			UserResourceId: reaction.User,
			Content:        reaction.Content,
			CreatedAt:      toTimestamp(reaction.CreatedAt),
		})
	}

	return v1Reactions
}
