package twirp

import (
	"context"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/proto"
	"github.com/github/turboscan/ts/twirp/twerrors"
	"github.com/jinzhu/gorm"
	"github.com/pkg/errors"
)

func (r *ResultsResolver) GetDelivery(ctx context.Context, req *proto.DeliveryRequest) (*proto.DeliveryResponse, error) {
	ctx, span := o11y.StartSpan(ctx, o11y.WithRepoIDFromRequest(req))
	defer span.End()

	appctx.Logger(ctx).Info("request received",
		kvp.String("gh.turboscan.sarif_id", req.SarifId),
	)

	if req.RepositoryId == 0 {
		return nil, twerrors.RequiredArgumentError("repository_id")
	}
	sarifID, ok := ts.NewSarifID(req.SarifId)
	if !ok {
		return nil, twerrors.InvalidArgumentError("sarif_id", "invalid sarif_id")
	}
	if sarifID == "" {
		return nil, twerrors.RequiredArgumentError("sarif_id")
	}

	repositoryID := ts.RepositoryEID(req.RepositoryId)

	delivery, err := r.deliveryService.GetDelivery(ctx, repositoryID, sarifID)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, o11y.RecordError(span, twerrors.NotFoundError("No data found for the provided repository and SARIF ID."))
		} else {
			return nil, o11y.RecordError(span, err)
		}
	}

	// First count the (complete) analyses
	filter := ts.AnalysisFilter{
		RepositoryID:    repositoryID,
		SarifID:         &sarifID,
		State:           ts.AnalysisStateFilterComplete,
		IncludeOutdated: true,
	}

	count, err := r.alertService.CountAnalyses(ctx, filter)
	if err != nil {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}

	// Now retrieve details of any process errors.
	// This includes delivery errors, so we can provide helpful info
	// even if no analyses are present.
	pErrs, err := r.alertService.ProcessErrorsForSarifId(repositoryID, sarifID)
	if err != nil {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}

	return &proto.DeliveryResponse{
		AnalysisCount: count,
		Errors:        serializeProcessErrors(pErrs),
		Ref:           delivery.Ref,
	}, nil
}
