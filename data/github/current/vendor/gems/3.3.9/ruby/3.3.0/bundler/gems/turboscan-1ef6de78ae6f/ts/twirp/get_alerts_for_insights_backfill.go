package twirp

import (
	"context"

	"github.com/github/github-telemetry-go/kvp"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/elasticsearch"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/proto"
	"github.com/github/turboscan/ts/twirp/tstypes"
	"github.com/github/turboscan/ts/twirp/twerrors"
)

// GetAlertsForInsightsBackfill returns alerts for the default branch of a given repository in a shape that is suitable for Insights backfill data ingestion.
func (r *ResultsResolver) GetAlertsForInsightsBackfill(ctx context.Context, req *proto.GetAlertsForInsightsBackfillRequest) (*proto.GetAlertsForInsightsBackfillRequestResponse, error) {
	// Insights backfill will iterate through an organization's repositories and call this endpoint for each repository.
	// github/security-center#1823
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	appctx.Logger(ctx).Info("request received",
		kvp.String("gh.turboscan.next_cursor", req.NextCursor),
		kvp.String("gh.turboscan.updated_after", req.UpdatedAfter.String()),
	)

	if req.RepositoryId == 0 {
		return nil, o11y.RecordError(span, twerrors.RequiredArgumentError("repository_id"))
	}

	filter := &ts.SearchByOrgsFilter{
		RepositoryIDs: []ts.RepositoryEID{ts.RepositoryEID(req.RepositoryId)},
		IncludeRepositoriesWithoutCodeScanningEnabled: true,
	}

	pagination, err := toPagination(req)
	if err != nil {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}

	var sort ts.SearchResultsSort
	if req.UpdatedAfter == nil {
		// For full reconciliation, we need to purge orphaned alerts, so sorting by ID takes priority.
		sort = ts.SearchSortFromProto(proto.AlertSortOrder_CREATED_ASCENDING)
	} else {
		// Because our cursors are timestamp-based, so too must be the sort
		sort = ts.SearchSortFromProto(proto.AlertSortOrder_UPDATED_ASCENDING)
	}

	// Using org search so we only retrieve alerts for the default branch ref of the repository
	searchResult, err := r.es.SearchOrgAlerts(ctx, filter, *pagination, sort)
	if err != nil {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}

	searchDocuments := searchResult.Documents

	insightsAlerts := []*proto.InsightsAlert{}
	for _, searchDocument := range searchDocuments {
		updatedAlert, createdAlert, err := serializeSearchDocumentForInsights(searchDocument)
		if err != nil {
			return nil, o11y.RecordError(span, err)
		}

		insightsAlerts = append(insightsAlerts, updatedAlert)
		if createdAlert != nil {
			insightsAlerts = append(insightsAlerts, createdAlert)
		}
	}

	return &proto.GetAlertsForInsightsBackfillRequestResponse{
		Alerts:     insightsAlerts,
		NextCursor: searchResult.NextCursor,
	}, nil
}

func toPagination(req *proto.GetAlertsForInsightsBackfillRequest) (*ts.Pagination, error) {
	limit := ts.MAX_PAGE_SIZE
	pagination, err := tstypes.CreateCursorPaginationInfo(limit, "", req.NextCursor)
	if err != nil {
		return nil, err
	}

	if pagination.Cursor != nil {
		return &pagination, nil
	}

	// To support periodic reconciliation, we need to be able to filter alerts by updated_at.
	// In practice, this value will be the last time the consumer reconciled alert data.
	// If provided, we'll use the UpdatedAfter value to construct a pseudo-cursor.
	if req.UpdatedAfter != nil {
		unixMilli := req.UpdatedAfter.AsTime().UnixMilli()
		initialAlertId := uint64(0)
		cursor := elasticsearch.Cursor{
			UpdatedAt: &unixMilli,
			AlertID:   &initialAlertId,
		}
		cursorStr, err := elasticsearch.EncodeCursor(cursor)
		if err != nil {
			return nil, err
		}

		pagination.Cursor = &ts.SerializedCursor{
			String:     cursorStr,
			Descending: false,
		}
	}

	return &pagination, nil
}
