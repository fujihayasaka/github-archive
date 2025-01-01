package servermigrator

import (
	"fmt"
	"iter"

	"github.com/github/migrations-vnext/internal/pkg/adapters/googlegithub"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	ogithub "github.com/google/go-github/v65/github"
	"github.com/google/uuid"
)

const reactionBatchSize = 100

// reactionBatcher is a function that transforms sequence of reactions into a sequence of resources.
// It is used to batch reactions into a single resource.
func (r *ResourceFetcher) reactionBatcher(
	reactions iter.Seq[*ogithub.Reaction],
	subjectType v1.ReactionSubjectType,
	subjectID string,
) iter.Seq[*v1.Resource] {
	return func(yield func(*v1.Resource) bool) {
		batches := batchIter(reactions, reactionBatchSize)
		for batch := range batches {
			if len(batch) == 0 {
				continue
			}
			var b []*v1.Reaction
			for _, reaction := range batch {
				conv, err := googlegithub.Reaction{Reaction: *reaction}.ToV1Reaction()
				if err != nil {
					r.err = fmt.Errorf("error converting to v1.Reaction: %w", err)
					return
				}
				b = append(b, conv)
			}
			resource := &v1.Resource{
				Resource: &v1.Resource_ReactionsBatch{
					ReactionsBatch: &v1.ReactionsBatch{
						ResourceId:        fmt.Sprintf("reactions-%s-%s", subjectID, uuid.New().String()),
						SubjectType:       subjectType,
						SubjectResourceId: subjectID,
						Reactions:         b,
					},
				},
			}
			if !yield(resource) {
				return
			}
		}
	}
}
