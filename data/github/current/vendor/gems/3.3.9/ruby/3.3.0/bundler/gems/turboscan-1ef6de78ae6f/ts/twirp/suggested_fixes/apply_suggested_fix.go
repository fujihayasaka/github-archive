package suggested_fixes

import (
	"context"
	"fmt"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/jobs"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/proto"
	"github.com/github/turboscan/ts/twirp/twerrors"
	"github.com/pkg/errors"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
)

// ApplySuggestedFix marks an alert suggestion as applied
func (s *Service) ApplySuggestedFix(ctx context.Context, req *proto.ApplySuggestedFixRequest) (*proto.ApplySuggestedFixResponse, error) {
	ctx, span := o11y.StartSpan(ctx,
		o11y.WithRepoIDFromRequest(req),
		trace.WithAttributes(attribute.Int("gh.turboscan.alert_number", int(req.AlertNumber))),
	)
	defer span.End()

	appctx.Logger(ctx).Info("request received",
		ts.RepositoryEID(req.RepositoryId).AsKVP(),
		kvp.Uint32("gh.turboscan.alert_number", req.AlertNumber),
		kvp.ByteStrings("gh.git.ref", req.RefNamesBytes),
	)

	if req.RepositoryId == 0 {
		return nil, twerrors.RequiredArgumentError("repository_id")
	}

	if req.AlertNumber == 0 {
		return nil, twerrors.RequiredArgumentError("alert_number")
	}

	if len(req.RefNamesBytes) == 0 {
		return nil, twerrors.RequiredArgumentError("ref_names_bytes")
	}

	if req.ActorId == 0 {
		return nil, twerrors.RequiredArgumentError("actor_id")
	}

	repoID := ts.RepositoryEID(req.RepositoryId)
	err := s.sf.ApplySuggestedFix(ctx, repoID, req.AlertNumber, req.RefNamesBytes, ts.UserEID(req.ActorId))
	if err != nil {
		appctx.Logger(ctx).Error("Failed to apply a suggested fix",
			ts.RepositoryEID(req.RepositoryId).AsKVP(),
		)
	}
	// The success of the request depends on the result of the apply operation
	// if we fail later the the request is still considered successful
	requestSuccessful := err == nil

	alertNumbers := []uint32{req.AlertNumber}
	payload := map[string]string{
		"repository_id": fmt.Sprintf("%d", req.RepositoryId),
	}
	err = s.sf.GitHubTwirpApiClient.SuggestedFixStateChanged(ctx, repoID, 0, alertNumbers)
	if err != nil {
		appctx.Report(ctx, errors.Wrap(err, "Failed to call internal Monolith Twirp service"), payload)
	}

	// Index the alerts that got an updated suggested fix
	indexJob := &jobs.AlertIndexing{
		Context:             "apply-suggested-fix",
		RepositoryID:        repoID,
		LogicalAlertNumbers: alertNumbers,
	}
	_, err = s.aqueduct.PerformLater(ctx, indexJob)
	if err != nil {
		appctx.Report(ctx, errors.Wrap(err, "Failed to enqueue indexing job"), payload)
	}

	return &proto.ApplySuggestedFixResponse{
		Success: requestSuccessful,
	}, nil
}
