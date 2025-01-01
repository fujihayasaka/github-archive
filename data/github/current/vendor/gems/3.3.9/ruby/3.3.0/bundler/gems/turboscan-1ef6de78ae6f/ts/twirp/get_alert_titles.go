package twirp

import (
	"context"
	"fmt"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/mysql/alert"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/proto"
	"github.com/github/turboscan/ts/twirp/twerrors"
)

func (r *ResultsResolver) GetAlertTitles(ctx context.Context, req *proto.AlertTitlesRequest) (*proto.AlertTitlesResponse, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	alertNumbers := req.AlertNumbers
	repositoryIds := req.RepositoryIds

	appctx.Logger(ctx).Info("request received",
		kvp.String("gh.turboscan.alert_numbers", fmt.Sprint(alertNumbers)),
	)

	if len(alertNumbers) == 0 {
		return nil, twerrors.RequiredArgumentError("alert_numbers")
	}
	if len(alertNumbers) != len(repositoryIds) {
		return nil, twerrors.InvalidArgumentError("alert_numbers", "must be the same length as repository_ids")
	}
	for _, a := range req.AlertNumbers {
		if a == 0 {
			return nil, twerrors.InvalidArgumentError("alert_number", "must be > 0")
		}
	}
	for _, r := range req.RepositoryIds {
		if r == 0 {
			return nil, twerrors.InvalidArgumentError("repository_id", "must be > 0")
		}
	}

	// group alert numbers by repo
	alertsByRepo := make(map[ts.RepositoryEID][]uint32)
	for i, repo := range repositoryIds {
		repoId := ts.RepositoryEID(repo)
		alertsByRepo[repoId] = append(alertsByRepo[repoId], alertNumbers[i])
	}

	alertTitles := make(map[ts.RepositoryEID]map[uint32]string)

	options := &ts.FindOptions{
		Preloads: []string{"Rule"},
		SortBy:   alert.SortBy(proto.AlertSortOrder_CREATED_ASCENDING),
	}

	// run one query per repo
	for repoId, alertsForRepo := range alertsByRepo {
		if err := appctx.ContextError(ctx, "get_alert_titles"); err != nil {
			return nil, err
		}

		alertFilter := ts.AlertFilter{
			Numbers: alertsForRepo,
		}
		analysisFilter := ts.AnalysisFilter{
			RepositoryID:    repoId,
			State:           ts.AnalysisStateFilterSuccessful,
			IncludeOutdated: true,
		}

		alertsInRepo, err := r.alertService.Alerts(ctx, repoId, alertFilter, analysisFilter, options)
		if err != nil {
			return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
		}

		titles := make(map[uint32]string)
		for _, a := range alertsInRepo {
			titles[a.Number] = a.Rule.ShortDescription
		}
		alertTitles[repoId] = titles
	}

	return serializeAlertTitles(alertTitles), nil
}
