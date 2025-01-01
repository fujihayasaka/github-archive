package resource

import (
	"context"
	"fmt"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/migrations-vnext/internal/pkg/client"
	octov1 "github.com/github/migrations-vnext/internal/pkg/octoshift/imports/v1"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
)

type reactionsBatch struct {
	baseHandler
	pb *v1.ReactionsBatch
}

var _ handler = (*reactionsBatch)(nil)

func newReactionsBatch(pb *v1.ReactionsBatch, logger log.Logger) *reactionsBatch {
	return &reactionsBatch{
		baseHandler: baseHandler{logger},
		pb:          pb,
	}
}

func (r *reactionsBatch) resourceID() string {
	return r.pb.ResourceId
}

func (r *reactionsBatch) dependencies() (*transformedDeps, error) {
	deps := newTransformedDeps()
	deps.int64Deps.Add(r.pb.SubjectResourceId)

	for _, reaction := range r.pb.Reactions {
		deps.strDeps.Add(reaction.UserResourceId)
	}
	return deps, nil
}

func (r *reactionsBatch) load(ctx context.Context, importer client.Importer, resolved resolvedIDsByResource) error {
	batch, err := toOctoReactionBatch(r.pb.Reactions, resolved)
	if err != nil {
		return fmt.Errorf("failed to transform reactions: %w", err)
	}

	reactionsReq := &octov1.ImportReactionsRequest{
		SubjectType: octov1.ReactionSubjectType(r.pb.SubjectType),
		SubjectId:   resolved[r.pb.SubjectResourceId].int64Val,
		Reactions:   batch,
	}

	_, err = importer.ImportReactions(ctx, reactionsReq)
	if err != nil {
		r.logger.WithError(err).Error("failed to import reactions", kvp.Any("request", reactionsReq))
		return fmt.Errorf("failed to load reactions: %w", err)
	}
	return nil
}

func toOctoReactionBatch(reactions []*v1.Reaction, resolved resolvedIDsByResource) ([]*octov1.ReactionBatch, error) {
	var batch []*octov1.ReactionBatch
	for _, r := range reactions {
		var val octov1.ReactionContent
		switch r.Content {
		case "+1":
			val = octov1.ReactionContent_REACTION_CONTENT_THUMBS_UP
		case "-1":
			val = octov1.ReactionContent_REACTION_CONTENT_THUMBS_DOWN
		case "laugh":
			val = octov1.ReactionContent_REACTION_CONTENT_LAUGH
		case "tada":
			val = octov1.ReactionContent_REACTION_CONTENT_TADA
		case "thinking_face":
			val = octov1.ReactionContent_REACTION_CONTENT_CONFUSED
		case "heart":
			val = octov1.ReactionContent_REACTION_CONTENT_HEART
		case "rocket":
			val = octov1.ReactionContent_REACTION_CONTENT_ROCKET
		case "eyes":
			val = octov1.ReactionContent_REACTION_CONTENT_EYES
		default:
			// REACTION_CONTENT_INVALID exists in the spec but will cause
			// errors in the reactions API. Let's just skip invalid reactions here.
			continue
		}
		batch = append(batch, &octov1.ReactionBatch{
			UserLogin: resolved[r.UserResourceId].strVal,
			Content:   val,
			CreatedAt: r.CreatedAt,
		})
	}
	return batch, nil
}
