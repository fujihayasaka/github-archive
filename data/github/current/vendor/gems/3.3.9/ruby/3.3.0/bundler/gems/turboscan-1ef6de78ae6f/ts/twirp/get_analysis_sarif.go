package twirp

import (
	"bytes"
	"context"
	"regexp"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/proto"
	"github.com/github/turboscan/ts/sarif"
	"github.com/github/turboscan/ts/twirp/twerrors"
	"github.com/pkg/errors"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
)

func downloadWithTiming(fn func() (*bytes.Buffer, error)) (time.Duration, *bytes.Buffer, error) {
	startTime := time.Now()
	content, err := fn()
	return time.Since(startTime), content, err
}

func (r *ResultsResolver) GetAnalysisSarif(ctx context.Context, req *proto.AnalysisSarifRequest) (*proto.AnalysisSarifResponse, error) {
	ctx, span := o11y.StartSpan(ctx,
		o11y.WithRepoIDFromRequest(req),
		trace.WithAttributes(attribute.Int("gh.turboscan.analysis_id", int(req.AnalysisId))),
	)
	defer span.End()

	appctx.Logger(ctx).Info("request received",
		kvp.Uint64("gh.turboscan.analysis_id", req.AnalysisId),
	)

	if req.RepositoryId == 0 {
		return nil, twerrors.RequiredArgumentError("repository_id")
	}

	if req.AnalysisId == 0 {
		return nil, twerrors.RequiredArgumentError("analysis_id")
	}

	repositoryID := ts.RepositoryEID(req.RepositoryId)
	analysisID := ts.AnalysisID(req.AnalysisId)

	opts := sarif.BuildSarifOpts{
		RepoHTMLURL: req.RepoHtmlUrl,
		AlertAPIURL: req.AlertsApiUrl,
	}

	// read processed sarif from sarif store
	as, err := r.alertService.FindAnalyses(ctx, ts.AnalysisFilter{
		AnalysisIDs:     []ts.AnalysisID{analysisID},
		RepositoryID:    repositoryID,
		State:           ts.AnalysisStateFilterSuccessful,
		IncludeOutdated: true,
	}, &ts.FindOptions{})
	if err != nil {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}
	if len(as) == 0 {
		return nil, o11y.RecordError(span, twerrors.NotFoundError("analysis not found"))
	}
	rawAnalysis := as[0]
	if rawAnalysis.ArchivalDataUrl != "" {
		sarifStr, err := r.downloadAndDecodeSarif(ctx, rawAnalysis, opts)
		if err != nil {
			appctx.Logger(ctx).WithError(err).Error("failed to download processed sarif for historic analysis",
				rawAnalysis.RepositoryID.AsKVP(),
				rawAnalysis.ID.AsKVP(),
			)
			return nil, twerrors.InternalErrorWith(err)
		} else {
			return &proto.AnalysisSarifResponse{Sarif: sarifStr}, nil
		}
	}

	analysis, err := r.archiveService.LoadAnalysis(ctx, repositoryID, analysisID, false)
	if err != nil {
		if errors.Is(err, ts.ErrAnalysisNotFound) {
			return nil, o11y.RecordError(span, twerrors.NotFoundError("analysis not found"))
		}
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}

	sarifStr, err := sarif.BuildSarif(analysis, opts)
	if err != nil {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}
	return &proto.AnalysisSarifResponse{Sarif: sarifStr}, nil
}

func (r *ResultsResolver) downloadAndDecodeSarif(ctx context.Context, analysis ts.Analysis, opts sarif.BuildSarifOpts) (string, error) {
	appctx.Logger(ctx).Info("downloading historic analysis", analysis.ID.AsKVP())
	appctx.Stats(ctx).Counter("get_analysis_sarif.download.started", nil, 1)
	duration, content, err := downloadWithTiming(func() (*bytes.Buffer, error) {
		return r.archivalStore.Download(ctx, analysis.ArchivalDataUrl)
	})
	appctx.Stats(ctx).DistributionMs("get_analysis_sarif.download.completed", buildTags(err), duration)
	if err != nil {
		return "", err
	}
	appctx.Logger(ctx).Info("download processed sarif succeeded for historic analysis",
		analysis.RepositoryID.AsKVP(),
		analysis.ID.AsKVP(),
		kvp.Float64("gh.operation.duration", float64(duration)),
	)

	sarifStr := content.String()
	re := regexp.MustCompile(`\$repoHtmlUrl`)
	sarifStr = re.ReplaceAllString(sarifStr, opts.RepoHTMLURL)
	re = regexp.MustCompile(`\$alertApiUrl`)
	sarifStr = re.ReplaceAllString(sarifStr, opts.AlertAPIURL)
	return sarifStr, nil
}

func buildTags(err error) stats.Tags {
	if err != nil {
		return stats.Tags{"result": "success"}
	}
	return stats.Tags{"result": "failure"}
}
