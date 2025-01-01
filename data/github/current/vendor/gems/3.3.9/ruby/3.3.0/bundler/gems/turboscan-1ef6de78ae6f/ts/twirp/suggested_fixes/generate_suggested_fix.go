package suggested_fixes

import (
	"context"
	"fmt"
	"strconv"

	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
	"golang.org/x/exp/maps"

	"github.com/SamuelTissot/sqltime"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/pkg/errors"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/jobs"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/proto"
	"github.com/github/turboscan/ts/transforms"
	"github.com/github/turboscan/ts/twirp/clients/aqueduct"
	"github.com/github/turboscan/ts/twirp/twerrors"
)

func (s *Service) GenerateSuggestedFix(ctx context.Context, req *proto.GenerateSuggestedFixRequest) (*proto.GenerateSuggestedFixResponse, error) {
	ctx, span := o11y.StartSpan(ctx,
		o11y.WithRepoIDFromRequest(req),
		trace.WithAttributes(
			attribute.Int("gh.pull_request.id", int(req.PullRequestId)),
			attribute.Int("gh.security_campaign_id", int(req.SecurityCampaignId)),
		),
	)
	defer span.End()

	requestedAt := sqltime.Now()
	repo := ts.RepositoryEID(req.RepositoryId)
	pullRequestId := ts.PullRequestEID(req.PullRequestId)

	ctx = appctx.With(ctx,
		repo.AsKVP(),
		kvp.Uint32s("gh.turboscan.alert_numbers", req.AlertNumbers),
		kvp.ByteStrings("gh.turboscan.ref_names", req.RefNamesBytes),
		pullRequestId.AsKVP(),
		kvp.Uint64("gh.security_campaign.id", req.SecurityCampaignId),
		kvp.Uint64("gh.user.id", req.UserId),
		kvp.String("gh.turboscan.suggested_fix_source", req.Source.String()),
	)

	appctx.Logger(ctx).Info("request received")

	if req.RepositoryId == 0 {
		return nil, twerrors.RequiredArgumentError("repository_id")
	}

	if len(req.AlertNumbers) == 0 {
		return nil, twerrors.RequiredArgumentError("alert_numbers")
	}

	if len(req.RefNamesBytes) == 0 {
		return nil, twerrors.RequiredArgumentError("ref_names_bytes")
	}

	err := s.emitAutofixGenerateHydroEvents(
		ctx,
		repo,
		req.AlertNumbers,
		req.RefNamesBytes,
		req.Source,
		pullRequestId,
		req.SecurityCampaignId,
	)
	if err != nil {
		appctx.Logger(ctx).WithError(err).Error("failed to emit hydro stats for autofix generation")
	}

	isPublicRepo := req.Public
	isCampaign := req.Source == proto.SuggestedFixSource_SUGGESTED_FIX_SOURCE_SECURITY_CAMPAIGN
	isOndemandApi := req.Source == proto.SuggestedFixSource_SUGGESTED_FIX_SOURCE_ONDEMAND_API

	// We need to process alerts individually because when we create SFAs we limit to 20 physical alerts which means
	// that we would only ever process a maximum of 20 alerts. That area of the code is being refactored so this is temporary.
	// See https://github.com/github/code-scanning/issues/14490
	for _, alertNumber := range req.AlertNumbers {
		err := s.processAlert(ctx, req.UserId, repo, pullRequestId, req.RefNamesBytes, alertNumber, isCampaign, isPublicRepo, isOndemandApi, requestedAt)
		if err != nil {
			return nil, o11y.RecordError(span, err)
		}
	}

	payload := map[string]string{
		"repository_id":   fmt.Sprintf("%d", req.RepositoryId),
		"pull_request_id": fmt.Sprintf("%d", req.PullRequestId),
		"campaign_id":     fmt.Sprintf("%d", req.SecurityCampaignId),
	}
	err = s.sf.GitHubTwirpApiClient.SuggestedFixStateChanged(ctx, repo, ts.PullRequestEID(req.PullRequestId), req.AlertNumbers)

	if err != nil {
		appctx.Report(ctx, errors.Wrap(err, "Failed to call internal Monolith Twirp service"), payload)
	}

	// Index the alerts that got an updated suggested fix
	indexJob := &jobs.AlertIndexing{
		Context:             "generate-suggested-fix",
		RepositoryID:        repo,
		LogicalAlertNumbers: req.AlertNumbers,
	}
	_, err = s.aqueduct.PerformLater(ctx, indexJob)
	if err != nil {
		appctx.Report(ctx, errors.Wrap(err, "Failed to enqueue indexing job"), payload)
	}

	return &proto.GenerateSuggestedFixResponse{
		Success: true,
	}, nil
}

func (s *Service) processAlert(
	ctx context.Context,
	userId uint64,
	repoId ts.RepositoryEID,
	pullRequestId ts.PullRequestEID,
	refNamesBytes [][]byte,
	alertNumber uint32,
	isCampaign bool,
	isPublicRepo bool,
	isOndemandApi bool,
	requestedAt sqltime.Time) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	ctx = appctx.With(ctx,
		repoId.AsKVP(),
		kvp.Uint32("gh.turboscan.alert_number", alertNumber),
		kvp.ByteStrings("gh.turboscan.ref_names", refNamesBytes),
	)

	appctx.Logger(ctx).Info("Processing alert")

	incrementStatsCounter(ctx, "candidate", isCampaign, 1)
	res, err := s.sf.CreateSFAsForAlerts(ctx, repoId, refNamesBytes, []uint32{alertNumber}, requestedAt)

	if err != nil {
		return o11y.RecordError(span, err)
	}

	physicalAlertIDs := transforms.Map(maps.Keys(res.PhysicalAlerts), func(pId ts.PhysicalAlertID) uint64 { return uint64(pId) })
	suggestedFixAlertIDs := transforms.Map(maps.Values(res.GenerateFixForSfaIds), func(sfaId ts.SuggestedFixAlertID) uint64 { return uint64(sfaId) })

	appctx.Logger(ctx).Info("Enqueue SuggestedFixAlertGenerateJob for physical alerts",
		kvp.Uint64s("gh.turboscan.physical_alert_ids", physicalAlertIDs),
		kvp.Uint64s("gh.turboscan.suggested_fix_alert_ids", suggestedFixAlertIDs),
	)

	for paId, sfaId := range res.GenerateFixForSfaIds {
		ctx := appctx.With(ctx,
			kvp.Uint64("gh.turboscan.physical_alert_id", uint64(paId)),
			kvp.Uint64("gh.turboscan.suggested_fix_alert_id", uint64(sfaId)),
		)

		if _, ok := res.PhysicalAlerts[paId]; !ok {
			appctx.Logger(ctx).Warn("Missing physical alert for suggested fix alert")

			incrementStatsCounter(ctx, "missing", isCampaign, 1)
			continue
		}
		pa := res.PhysicalAlerts[paId]
		tv := pa.Analysis.ToolVersion

		var job aqueduct.EnqueableJob
		if isCampaign || isPublicRepo || isOndemandApi {
			job = jobs.SuggestedFixAlertGenerateLowPriorityJob{
				RepoID:              repoId,
				CommitOid:           pa.Analysis.CommitOid,
				ToolName:            tv.Name.String(),
				ToolVersion:         tv.GetVersion(),
				PullRequestID:       pullRequestId,
				UserID:              userId,
				SuggestedFixAlertID: sfaId,
			}
		} else {
			job = jobs.SuggestedFixAlertGenerateHighPriorityJob{
				RepoID:              repoId,
				CommitOid:           pa.Analysis.CommitOid,
				ToolName:            tv.Name.String(),
				ToolVersion:         tv.GetVersion(),
				PullRequestID:       pullRequestId,
				UserID:              userId,
				SuggestedFixAlertID: sfaId,
			}
		}

		_, err = s.aqueduct.PerformLater(ctx, job)
		if err != nil {
			return err
		}

		incrementStatsCounter(ctx, "enqueued", isCampaign, 1)
	}

	if len(res.SkippedAlerts) > 0 {
		incrementStatsCounter(ctx, "skipped_alert", isCampaign, int64(len(res.SkippedAlerts)))
		appctx.Logger(ctx).Info("Skipped generating suggested fixes for unsupported rules or languages",
			kvp.Uint64s("gh.turboscan.alert_numbers", res.SkippedAlerts),
		)
	}

	if len(res.SfaExistForAlerts) > 0 {
		incrementStatsCounter(ctx, "exists", isCampaign, int64(len(res.SfaExistForAlerts)))
		appctx.Logger(ctx).Info("SuggestedFixAlert exists for alerts",
			kvp.Uint64s("gh.turboscan.alert_numbers", res.SfaExistForAlerts),
		)
	}

	return nil
}

func incrementStatsCounter(ctx context.Context, kind string, isCampaign bool, value int64) {
	appctx.Stats(ctx).Counter("suggested_fix.generation", stats.Tags{"kind": kind, "isCampaign": strconv.FormatBool(isCampaign)}, value)
}
