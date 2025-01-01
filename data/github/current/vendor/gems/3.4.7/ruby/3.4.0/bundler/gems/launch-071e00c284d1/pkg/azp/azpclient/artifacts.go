package azpclient

import (
	"context"
	"fmt"
	"net/http"
	"strings"

	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/pkg/azp"
	"github.com/github/launch/pkg/launchhttp/httpclient"
)

type ArtifactsService struct {
	client *Client
	http   *httpclient.Client
}

func (a *ArtifactsService) DeleteArtifact(ctx context.Context, workflowRunID string, artifactName string) error {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	opname := "artifacts.delete"

	if strings.TrimSpace(workflowRunID) == "" {
		return tracing.RecordError(span, fmt.Errorf("the workflow run id cannot be empty"))
	}

	url := a.client.url.getDeleteArtifactURL(workflowRunID, artifactName)

	err := a.deleteArtifact(ctx, url, opname)

	if err != nil {
		return tracing.RecordError(span, err)
	}

	return nil
}

func (a *ArtifactsService) DeleteArtifactByPlanID(ctx context.Context, planID string, artifactName string) error {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	opname := "artifacts.delete_by_plan_id"

	if strings.TrimSpace(planID) == "" {
		return fmt.Errorf("the planID cannot be empty")
	}

	url := a.client.url.getDeleteArtifactURLByPlanID(planID, artifactName)
	err := a.deleteArtifact(ctx, url, opname)

	if err != nil {
		return tracing.RecordError(span, err)
	}

	return nil
}

func (a *ArtifactsService) deleteArtifact(ctx context.Context, url, opname string) error {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	err := a.http.Do(
		ctx,
		opname,
		http.MethodDelete,
		url,
		nil,
		nil,
		a.client.withDefaultOpts(
			ctx,
			httpclient.WithValidator(func(r *http.Response) (bool, error) {
				if r.StatusCode == http.StatusNoContent {
					return false, nil
				}

				if r.StatusCode == http.StatusNotFound {
					// don't treat 404 as error
					return false, nil
				}

				return azp.ResponseValidator()(r)
			}),
		)...,
	)

	if err != nil {
		return tracing.RecordError(span, err)
	}

	return nil
}
