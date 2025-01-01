package azp

import (
	"context"
)

type ArtifactsClient interface {
	DeleteArtifact(ctx context.Context, workflowRunID string, artifactName string) error
	DeleteArtifactByPlanID(ctx context.Context, planID string, artifactName string) error
}
