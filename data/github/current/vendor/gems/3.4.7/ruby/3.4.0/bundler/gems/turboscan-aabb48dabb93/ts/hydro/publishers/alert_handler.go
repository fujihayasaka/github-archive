// Package publishers contains logic to write events to Hydro
package publishers

import (
	"context"
	"encoding/json"
	"time"

	"github.com/google/uuid"
	"github.com/pkg/errors"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/timestamppb"
	"google.golang.org/protobuf/types/known/wrapperspb"

	"github.com/github/go-http/middleware/requestid"
	auditloghydro "github.com/github/hydro-schemas-go/hydro/schemas/audit_log/v2"
	auditloghydroentities "github.com/github/hydro-schemas-go/hydro/schemas/audit_log/v2/entities"
	oldtshydro "github.com/github/hydro-schemas-go/hydro/schemas/turboscan/v0"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/auditlog"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/twirp"
)

type AlertPublisher interface {
	AlertEvent(context.Context, *oldtshydro.AlertEvent) error
	AuditEntry(context.Context, *auditloghydro.AuditEntry) error
	Flush() error
}

type HydroAlertEventHandler struct {
	publisher AlertPublisher
}

func NewHydroAlertHandler(p AlertPublisher) ts.AlertEventHandler {
	return &HydroAlertEventHandler{
		publisher: p,
	}
}

// NewAlertEvent is a producer function, that will be called when new alert events happen
// and is responsible to generate new alert events into the Hydro topic
func (a *HydroAlertEventHandler) NewAlertEvent(ctx context.Context, la *ts.LogicalAlert, event *ts.TimelineEvent) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	e := &oldtshydro.AlertEvent{
		RepositoryId: int32(event.RepositoryID),
		AlertNumber:  int32(la.Number),
		Event:        alertEventType(event.EventType),
		CommitOid:    event.CommitOid.String(),
		Ref:          event.Ref,
	}

	if event.EventType != ts.TimelineEventTypeAlertDeletedByUser {
		// Skip full serialization for deletion event, as we might not have
		// physical alerts associated.
		result, err := serializeResult(*la)
		if err != nil {
			return err
		}
		e.Result = result
	}

	if event.UserID != nil {
		e.ActorId = uint32(*event.UserID)
	}

	if event.NonUnique {
		// To avoid huge amounts of webhook spam, we don't emit an alert event for alerts that already exist and were simply detected in a new branch.
		// We could change this in future, but we'd need to be careful about the overall volume of webhooks we are sending.
		return nil
	}

	return a.publisher.AlertEvent(ctx, e)
}

// NewAuditEvents is a producer function, that will be called when new alert events happen
// and is responsible for generating audit log entries for each batch of events.
func (a *HydroAlertEventHandler) NewAuditEvents(ctx context.Context, batch ts.AuditEntryBatch, auditLogContext auditlog.AuditLogContext) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	var actorID uint32
	if batch.ActorID != nil {
		actorID = uint32(*batch.ActorID)
	}
	ae, err := createAuditEntry(ctx, batch.EventType, int32(batch.RepositoryID), batch.AlertNumbers, actorID, batch.CommitOID.String(), batch.Ref, auditLogContext, batch.DismissalApproverID)
	if err != nil {
		return err
	}
	err = a.publisher.AuditEntry(ctx, ae)
	if err != nil {
		return err
	}

	return nil
}

func (a *HydroAlertEventHandler) Flush() error {
	return a.publisher.Flush()
}

func alertEventType(t ts.TimelineEventType) oldtshydro.AlertEvent_EventType {
	switch t {
	case ts.TimelineEventTypeAlertAppearedInBranch:
		return oldtshydro.AlertEvent_ALERT_APPEARED_IN_BRANCH
	case ts.TimelineEventTypeAlertClosedBecameFixed, ts.TimelineEventTypeAlertClosedBecameOutdated:
		return oldtshydro.AlertEvent_ALERT_CLOSED_BECAME_FIXED
	case ts.TimelineEventTypeAlertResolvedByUser:
		return oldtshydro.AlertEvent_ALERT_CLOSED_BY_USER
	case ts.TimelineEventTypeAlertCreated:
		return oldtshydro.AlertEvent_ALERT_CREATED
	case ts.TimelineEventTypeAlertReappeared:
		return oldtshydro.AlertEvent_ALERT_REAPPEARED
	case ts.TimelineEventTypeAlertReopenedByUser:
		return oldtshydro.AlertEvent_ALERT_REOPENED_BY_USER
	case ts.TimelineEventTypeAlertDeletedByUser:
		return oldtshydro.AlertEvent_ALERT_DELETED_BY_USER
	case ts.TimelineEventTypeUnknown:
		return oldtshydro.AlertEvent_UNKNOWN
	default:
		return oldtshydro.AlertEvent_UNKNOWN
	}
}

func auditEntryAction(eventType ts.TimelineEventType) string {
	switch eventType {
	case ts.TimelineEventTypeAlertAppearedInBranch:
		return "code_scanning.alert_appeared_in_branch"
	case ts.TimelineEventTypeAlertClosedBecameFixed:
		return "code_scanning.alert_closed_became_fixed"
	case ts.TimelineEventTypeAlertClosedBecameOutdated:
		return "code_scanning.alert_closed_became_outdated"
	case ts.TimelineEventTypeAlertResolvedByUser:
		return "code_scanning.alert_closed_by_user"
	case ts.TimelineEventTypeAlertCreated:
		return "code_scanning.alert_created"
	case ts.TimelineEventTypeAlertReappeared:
		return "code_scanning.alert_reappeared"
	case ts.TimelineEventTypeAlertReopenedByUser:
		return "code_scanning.alert_reopened_by_user"
	case ts.TimelineEventTypeAlertDeletedByUser:
		return "code_scanning.alert_deleted_by_user"
	case ts.TimelineEventTypeUnknown:
		fallthrough
	default:
		return "code_scanning.unknown"
	}
}

type AuditEntryDocument struct {
	Timestamp      int64  `json:"@timestamp"`
	CatalogService string `json:"catalog_service"`
	RepositoryId   int32  `json:"repo_id"`
	// A list of affected alert numbers
	AlertNumbers []uint32 `json:"alert_numbers"`
	// The user who triggered the event
	ActorId uint32 `json:"actor_id,omitempty"`
	// Commit oid where the event happened
	CommitOid string `json:"commit_oid,omitempty"`
	// Ref where the event happened
	Ref string `json:"ref,omitempty"`
	// The request ID of the request that originated the event
	RequestID string `json:"request_id,omitempty"`
	auditlog.AuditLogContext
	// Dismissal approver who approved the dismissal request
	DismissalApproverID uint64 `json:"dismissal_approver_id,omitempty"`
}

func createAuditEntry(ctx context.Context, eventType ts.TimelineEventType, repositoryID int32, alertNumbers []uint32, actorID uint32, commitOID string, ref string, auditLogContext auditlog.AuditLogContext, dismissalApproverId *uint64) (*auditloghydro.AuditEntry, error) {
	now := time.Now()
	data := AuditEntryDocument{
		Timestamp:       now.UnixNano() / int64(time.Millisecond),
		CatalogService:  "github/code_scanning",
		RepositoryId:    repositoryID,
		AlertNumbers:    alertNumbers,
		ActorId:         actorID,
		CommitOid:       commitOID,
		Ref:             ref,
		RequestID:       requestid.GetGitHubRequestID(ctx),
		AuditLogContext: auditLogContext,
	}
	if dismissalApproverId != nil {
		data.DismissalApproverID = *dismissalApproverId
	}
	marshalledDocument, err := json.Marshal(data)
	if err != nil {
		return nil, err
	}
	documentId := uuid.New().String()
	return &auditloghydro.AuditEntry{
		Action:     wrapperspb.String(auditEntryAction(eventType)),
		EventTime:  timestamppb.New(now),
		Document:   wrapperspb.String(string(marshalledDocument)),
		DocumentId: wrapperspb.String(documentId),
		AuditLog:   auditloghydroentities.AuditLog_GITHUB,
	}, err
}

// Since the Twirp and Hydro Result message formats should be the same, we can
// re-use the twirp Result serializer to marshal the alert info for hydro
func serializeResult(la ts.LogicalAlert) (*oldtshydro.AlertEvent_Result, error) {
	var result oldtshydro.AlertEvent_Result

	twirpResult, err := twirp.GetMarshaledResult(la)
	if err != nil {
		return nil, err
	}
	if err = unwrapResultMessage(twirpResult, &result); err != nil {
		return nil, errors.Wrap(err, "unable to unwrap twirp result")
	}
	return &result, nil
}

// unwrapResultMessage unboxes a v1 or v2 protobuf message into a AlertEvent_Result
func unwrapResultMessage(data []byte, r *oldtshydro.AlertEvent_Result) error {
	return proto.Unmarshal(data, r)
}
