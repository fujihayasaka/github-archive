package resource

import (
	"context"
	"fmt"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/migrations-vnext/internal/pkg/client"
	"github.com/github/migrations-vnext/internal/pkg/keys"
	octov1 "github.com/github/migrations-vnext/internal/pkg/octoshift/imports/v1"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
)

type projectCardsBatch struct {
	baseHandler
	pb *v1.ProjectCardsBatch
}

var _ handler = (*projectCardsBatch)(nil)

func newProjectCardsBatch(pb *v1.ProjectCardsBatch, logger log.Logger) *projectCardsBatch {
	return &projectCardsBatch{
		baseHandler: baseHandler{logger},
		pb:          pb,
	}
}

func (p *projectCardsBatch) resourceID() string {
	return p.pb.ResourceId
}

func (p *projectCardsBatch) dependencies() (*transformedDeps, error) {
	deps := newTransformedDeps()
	deps.int64Deps.Add(p.pb.ProjectColumnResourceId)
	for _, card := range p.pb.Cards {
		deps.strDeps.Add(card.CreatorResourceId)
		if card.ContentResourceId != "" {
			deps.int64Deps.Add(card.ContentResourceId)
		}
	}

	return deps, nil
}

func (p *projectCardsBatch) load(ctx context.Context, importer client.Importer, resolved resolvedIDsByResource) error {
	var octoProjectCards []*octov1.ProjectCard

	for _, card := range p.pb.Cards {
		var contentID int64
		contentType := octov1.ContentType_CONTENT_TYPE_NOTE
		if card.ContentResourceId != "" {
			issueKey, err := keys.ToIssueKey(card.ContentResourceId)
			if err != nil {
				return fmt.Errorf("could not parse issue key: %w", err)
			}
			contentID = issueKey.Number
			contentType = octov1.ContentType_CONTENT_TYPE_ISSUE
		}
		octoProjectCards = append(octoProjectCards, &octov1.ProjectCard{
			CreatorLogin:   resolved[card.CreatorResourceId].strVal,
			ContentType:    contentType,
			ContentId:      contentID,
			Note:           card.Note,
			Priority:       card.Priority.Value,
			CreatedAt:      card.CreatedAt,
			UpdatedAt:      card.UpdatedAt,
			ArchivedAt:     card.ArchivedAt,
			HiddenAt:       card.HiddenAt,
			HasNilPriority: card.Priority == nil,
		})
	}

	req := &octov1.ImportProjectCardsRequest{
		ImportedProjectColumnId: resolved[p.pb.ProjectColumnResourceId].int64Val,
		ProjectCards:            octoProjectCards,
	}

	res, err := importer.ImportProjectCards(ctx, req)
	if err != nil {
		p.logger.WithError(err).Error("failed to import project cards", kvp.Any("request", req))
		return fmt.Errorf("failed to load project cards: %w", err)
	}
	if res.ProjectCardImportErrors != nil {
		for _, importErr := range res.ProjectCardImportErrors {
			p.logger.Error("failed to import project card",
				kvp.String("error_message", importErr.ErrorMessage),
				kvp.String("model_type", importErr.ModelType.String()),
			)
		}
	}

	return nil
}
