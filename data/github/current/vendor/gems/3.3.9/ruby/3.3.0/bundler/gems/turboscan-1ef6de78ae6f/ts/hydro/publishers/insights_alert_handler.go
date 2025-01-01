package publishers

import (
	"context"
	"strconv"
	"time"

	"github.com/github/turboscan/ts/appctx"

	"github.com/SamuelTissot/sqltime"
	"github.com/github/go-stats"
	insightshydro "github.com/github/hydro-schemas-go/hydro/schemas/github/security_center/v0"
	insightshydroentities "github.com/github/hydro-schemas-go/hydro/schemas/github/security_center/v0/entities"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/mysql/alert"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/proto"
	"github.com/github/turboscan/ts/twirp"
)

type InsightsPublisher interface {
	InsightsEntityBatchEvent(context.Context, *insightshydro.InsightsEntityBatch) error
}

// InsightsHydroAlertEventHandler is a serializer/handler for sending alert events to Insights Hydro topics
// See https://github.com/github/insights/blob/main/docs/engineering/design/cloud_ingestion/publishing_incremental_ingestion_events.md
// See https://github.com/github/insights/blob/main/docs/engineering/design/cloud_ingestion/staging_contracts/code_scanning.md
// Contributes to https://github.com/github/security-center/issues/1804
type InsightsHydroAlertEventHandler struct {
	publisher InsightsPublisher

	Alerts *alert.Service
}

const (
	InsightsAlertEntityName = "code_scanning_alert"
	entityEventsPageSize    = 500
)

func NewInsightsHydroAlertHandler(p InsightsPublisher, alertService *alert.Service) ts.InsightsHydroAlertEventHandler {
	return &InsightsHydroAlertEventHandler{
		publisher: p,
		Alerts:    alertService,
	}
}

// NewInsightsEntityBatchEvent is a producer function, that will be called when new alert events happen
// and is responsible to generate new alert events into the Security Center insights-handling topics
func (a *InsightsHydroAlertEventHandler) NewInsightsEntityBatchEvent(ctx context.Context, docs []*ts.SearchDocument, event_time time.Time) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	if event_time.IsZero() {
		event_time = time.Now().UTC()
	}

	// Iterate over alerts page by page
	for i := 0; i < len(docs); i += entityEventsPageSize {
		end := i + entityEventsPageSize
		if end > len(docs) {
			end = len(docs)
		}

		entities, err := a.getAlertFieldsHashes(ctx, docs[i:end], event_time)
		if err != nil {
			return err
		}
		e := &insightshydro.InsightsEntityBatch{
			Entity:          InsightsAlertEntityName,
			EntitiesUpdated: entities,
		}

		err = a.publisher.InsightsEntityBatchEvent(ctx, e)
		if err != nil {
			return err
		}
	}
	return nil
}

func (a *InsightsHydroAlertEventHandler) getAlertFieldsHashes(ctx context.Context, docs []*ts.SearchDocument, event_time time.Time) ([]*insightshydroentities.InsightsData, error) {
	var result []*insightshydroentities.InsightsData
	for _, doc := range docs {
		res := a.GetAlertFieldsHash(ctx, doc, event_time)
		result = append(result, res)
	}
	return result, nil
}

// GetAlertFieldsHash returns data payload with hash of the alert fields that are relevant for Insights
// The format and behavior of values of the hash matches InsightsAlert fields returned from twirp API as defined in insights.proto
func (a *InsightsHydroAlertEventHandler) GetAlertFieldsHash(ctx context.Context, doc *ts.SearchDocument, event_time time.Time) *insightshydroentities.InsightsData {
	closed, closedAt := doc.CalculateAlertClosure()
	var closedAtStr string
	if closedAt != nil {
		closedAtStr = closedAt.AsTime().Format(time.RFC3339Nano)
	}

	alertResolution, _ := ts.NewAlertResolution(doc.Resolution)
	serializedResolution := twirp.SerializeResolution(alertResolution)

	severity := proto.SecuritySeverity(proto.SecuritySeverity_value[doc.Severity])

	result := insightshydroentities.InsightsData{Data: map[string]string{
		"id":                     strconv.FormatUint(doc.AlertID, 10),
		"repository_id":          doc.RepositoryID,
		"created_at":             doc.CreatedAt.Format(time.RFC3339Nano),
		"updated_at":             doc.UpdatedAt.Format(time.RFC3339Nano),
		"resolution":             strconv.FormatInt(int64(serializedResolution), 10),
		"rule_name":              doc.RuleName,
		"rule_sarif_identifier":  doc.SarifIdentifier,
		"tool_name":              doc.Tool,
		"severity":               strconv.FormatUint(uint64(severity), 10),
		"closed_at":              closedAtStr,
		"closed":                 strconv.FormatBool(closed),
		"present_on_default_ref": strconv.FormatBool(doc.FixedOnDefault != nil),
		"source_time":            event_time.Format(time.RFC3339Nano),
		"number":                 strconv.FormatUint(uint64(doc.Number), 10),
	}}

	return &result
}

// EmitInsightsEvents sends events to Security Center hydro topic
// changedLogicalAlertIds is optional map of logical alert IDs that have changed, used to instrument the changes to Insights.
func (a *InsightsHydroAlertEventHandler) EmitInsightsEvents(ctx context.Context, docs []*ts.SearchDocument, changedLogicalAlertIds map[ts.LogicalAlertID]struct{}) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	defer a.duration(ctx, "emit-insights-events")()

	if len(docs) > 0 {

		// Filter out documents that have empty FixedOnDefault - which means they
		// don't exist on default branch.
		// Alerts that don't affect default branch are not setting this field to any value, and leave it as nil
		// Also filter out deleted events. The alert deletion functionality is deprecated,
		// but there are still some deleted alerts in the database/index
		// Also filter out alerts that are not in the changedLogicalAlertIds list, if it's provided
		filtered_docs := make([]*ts.SearchDocument, 0, len(docs))
		for _, doc := range docs {
			isChanged := true
			if changedLogicalAlertIds != nil {
				_, isChanged = changedLogicalAlertIds[ts.LogicalAlertID(doc.AlertID)]
			}

			if doc.FixedOnDefault != nil && (doc.Deleted == nil || !*doc.Deleted) && isChanged {
				filtered_docs = append(filtered_docs, doc)
			}
		}

		err := a.NewInsightsEntityBatchEvent(ctx, filtered_docs, time.Now().UTC())
		if err != nil {
			return err
		}

		appctx.Stats(ctx).Counter("insights.events", nil, int64(len(filtered_docs)))
	}
	return nil
}
func (a *InsightsHydroAlertEventHandler) EmitHydroEvents(ctx context.Context, docs []ts.SearchDocument, fields map[string]interface{}) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	defer a.duration(ctx, "emit-hydro-events")()

	docPointers := make([]*ts.SearchDocument, len(docs))
	for i := range docs {
		// Directly apply changes, in case ES hasn't reindexed data yet

		resolved, ok := fields["resolved"].(bool)
		if ok {
			docs[i].Resolved = &resolved
		}
		resolution, ok := fields["resolution"].(string)
		if ok {
			docs[i].Resolution = resolution
		}
		resolver_id, ok := fields["resolver_id"].(ts.UserEID)
		if ok {
			docs[i].ResolverID = &resolver_id
		}
		updated_at, ok := fields["updated_at"].(sqltime.Time)
		if ok {
			docs[i].UpdatedAt = &updated_at
		}
		resolved_at, ok := fields["resolved_at"].(sqltime.Time)
		if ok {
			docs[i].ResolvedAt = &resolved_at
		}

		docPointers[i] = &docs[i]
	}

	return a.EmitInsightsEvents(ctx, docPointers, nil)
}

func (a *InsightsHydroAlertEventHandler) duration(ctx context.Context, method string) func() {
	start := time.Now()
	return func() {
		if !appctx.IsShuttingDown(ctx) {
			appctx.Stats(ctx).DistributionMs("insights.request", stats.Tags{"method": method}, time.Since(start))
		}
	}
}

// NullHandler is a no-op implementation of InsightsHydroAlertEventHandler
type NullHandler struct{}

func (ih NullHandler) EmitInsightsEvents(ctx context.Context, docs []*ts.SearchDocument, changedLogicalAlertIds map[ts.LogicalAlertID]struct{}) error {
	return nil
}

func (ih NullHandler) EmitHydroEvents(ctx context.Context, docs []ts.SearchDocument, fields map[string]interface{}) error {
	return nil
}

func (ih NullHandler) NewInsightsEntityBatchEvent(ctx context.Context, docs []*ts.SearchDocument, event_time time.Time) error {
	return nil
}

func (ih NullHandler) GetAlertFieldsHash(ctx context.Context, doc *ts.SearchDocument, event_time time.Time) *insightshydroentities.InsightsData {
	return &insightshydroentities.InsightsData{}
}
