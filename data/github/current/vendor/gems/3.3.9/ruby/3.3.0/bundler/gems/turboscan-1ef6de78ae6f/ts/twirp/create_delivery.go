package twirp

import (
	"context"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/proto"
	"github.com/github/turboscan/ts/twirp/twerrors"
	"google.golang.org/protobuf/types/known/timestamppb"
)

func toOptionalTime(time *timestamppb.Timestamp) *time.Time {
	if time == nil {
		return nil
	}
	converted := time.AsTime()
	return &converted
}

func (r *ResultsResolver) CreateDelivery(ctx context.Context, req *proto.CreateDeliveryRequest) (*proto.CreateDeliveryResponse, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	appctx.Logger(ctx).Info("request received",
		kvp.String("gh.turboscan.sarif_id", req.SarifId),
	)

	if req.RepositoryId == 0 {
		return nil, twerrors.RequiredArgumentError("repository_id")
	}

	if req.CommitOid == "" {
		return nil, twerrors.RequiredArgumentError("commit_oid")
	}

	if len(req.Ref) == 0 {
		return nil, twerrors.RequiredArgumentError("ref")
	}

	if len(req.Ref) > ts.RefMaxSize {
		return nil, twerrors.InvalidArgumentError("ref", "ref is too long")
	}

	if req.UploadStartedAt == nil {
		return nil, twerrors.RequiredArgumentError("upload_started_at")
	}

	if req.UploadFinishedAt == nil {
		return nil, twerrors.RequiredArgumentError("upload_finished_at")
	}

	if req.HydroEnqueuedAt == nil {
		return nil, twerrors.RequiredArgumentError("hydro_enqueued_at")
	}

	sarifID, ok := ts.NewSarifID(req.SarifId)
	if !ok {
		return nil, twerrors.InvalidArgumentError("sarif_id", "invalid sarif_id")
	}
	if sarifID == "" {
		return nil, twerrors.RequiredArgumentError("sarif_id")
	}

	// SARIF is not provided in tombstone or error messages, so we allow this to be empty.
	if req.SarifPath == "" && req.OutdatedConfiguration == nil && !req.Rejected {
		return nil, twerrors.RequiredArgumentError("sarif_path")
	}

	environment := ts.AnalysisEnv{}
	if req.Environment != "" {
		// Errors are intentionally ignored here.
		// ts.AnalysisEnv is a map of string to string, however environments can legally be a map of string to any primitive type, or in reality actually be a map of strings to complex types too.
		_ = environment.Scan(req.Environment)
	}
	var outdatedConfiguration ts.OutdatedConfiguration
	if req.OutdatedConfiguration != nil {
		outdatedConfiguration.ToolName = ts.ToToolName(req.OutdatedConfiguration.ToolName)
		outdatedConfiguration.Category = ts.ToCategory(req.OutdatedConfiguration.Category)
	}

	delivery := ts.Delivery{
		CommitOid:             ts.ToSha(req.CommitOid),
		Ref:                   req.Ref,
		RepositoryID:          ts.RepositoryEID(req.RepositoryId),
		RepositoryNWO:         ts.ToRepositoryNWO(req.RepositoryNwo),
		SarifID:               sarifID,
		RequestID:             ts.ToRequestID(req.RequestId),
		AnalysisName:          ts.ToAnalysisName(req.AnalysisName),
		AnalysisKey:           ts.ToAnalysisKey(req.AnalysisKey),
		Environment:           environment,
		CheckoutURI:           ts.ToCheckoutURI(req.CheckoutUri),
		BuildStartedAt:        toOptionalTime(req.BuildStartedAt),
		WorkflowRunID:         ts.WorkflowRunEID(req.WorkflowRunId),
		WorkflowRunAttempt:    ts.WorkflowRunAttempt(req.WorkflowRunAttempt),
		UploadStartedAt:       toOptionalTime(req.UploadStartedAt),
		UploadFinishedAt:      toOptionalTime(req.UploadFinishedAt),
		HydroEnqueuedAt:       toOptionalTime(req.HydroEnqueuedAt),
		SarifPath:             req.SarifPath,
		SourceRepositoryID:    ts.RepositoryEID(req.SourceRepositoryId),
		OutdatedConfiguration: outdatedConfiguration,
	}

	if req.Rejected {
		delivery.Failed = true
		delivery.Complete = true
	}

	// Start Transitional code: This data should come as part of the request but for now it does not
	// See https://github.com/github/code-scanning/issues/7691
	delivery.Origin = delivery.OriginFromAnalysisKey()
	delivery.WorkflowPath = delivery.WorkflowPathFromAnalysisKey()
	// End Transitional code

	if err := r.deliveryService.CreateDelivery(ctx, &delivery); err != nil {
		return nil, err
	}

	resp := &proto.CreateDeliveryResponse{Id: uint64(delivery.ID)}

	switch deliveryError := req.Error.(type) {
	case nil:
		// no error
	case *proto.CreateDeliveryRequest_InvalidZipError:
		_, err := r.messageService.InvalidZip(ctx, &delivery, deliveryError.InvalidZipError.Empty)
		return resp, err
	case *proto.CreateDeliveryRequest_InvalidSarifError:
		_, err := r.messageService.SarifParsingFailed(ctx, &delivery, deliveryError.InvalidSarifError.Message)
		return resp, err
	case *proto.CreateDeliveryRequest_SarifTooBigError:
		_, err := r.messageService.SarifTooBig(ctx, &delivery, deliveryError.SarifTooBigError.Max)
		return resp, err
	case *proto.CreateDeliveryRequest_ZipTooBigError:
		_, err := r.messageService.ZipTooBig(ctx, &delivery, deliveryError.ZipTooBigError.Max)
		return resp, err
	}

	return resp, nil
}
