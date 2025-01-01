package deploy

import (
	"context"
	"encoding/json"
	"time"

	// nolint: staticcheck
	"github.com/golang/protobuf/proto"
	errs "github.com/pkg/errors"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/github/go-kvp"

	"github.com/github/launch/hydro/events"
	hydroV0 "github.com/github/launch/hydro/schemas/github/actions/v0"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/services/errors"
	pb "github.com/github/launch/services/pb/deploy"
)

func (s *service) AbuseDetectionStatus(ctx context.Context, req *pb.AbuseStatusRequest) (*pb.AbuseStatusResponse, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	res := &pb.AbuseStatusResponse{}

	validSignature, err := s.verifySignature(ctx, req)
	if err != nil {
		s.cfg.Log.Report(ctx, err)
		return res, errors.NewInternalError(err.Error())
	}
	res.ValidSignature = validSignature
	if !validSignature {
		s.cfg.Log.Error(ctx, "error validating signature for abuse detection status")
		return res, nil
	}

	if err := s.performUpload(ctx, req); err != nil {
		s.cfg.Log.Report(ctx, err)
		span.RecordError(err)
		return res, errors.NewInternalError(err.Error())
	}

	return res, nil
}

func (s *service) performUpload(ctx context.Context, req *pb.AbuseStatusRequest) error {
	incomingByTenantName, tenantIDs, err := s.parseIncomingAbuseMetrics(ctx, req.Status)
	if err != nil {
		s.cfg.Hydro.CountErroredEvent(events.AbuseDetectionStatusEvent)
		return err
	}

	if len(tenantIDs) == 0 {
		// nothing to do
		return nil
	}

	dbEntities, err := s.cfg.AZPResources.GetDataForAbuseHydro(ctx, tenantIDs)
	if err != nil {
		s.cfg.Hydro.CountErroredEvent(events.AbuseDetectionStatusEvent)
		return errs.Wrap(err, "failed to retrieve tenants from DB")
	}
	entityIDs := mapEntityIDs(dbEntities)

	s.countIncomingEntityTypes(ctx, entityIDs)

	ownersByEntityID, err := s.getBillingOwnersFromDotcom(ctx, entityIDs)
	if err != nil {
		s.cfg.Hydro.CountErroredEvent(events.AbuseDetectionStatusEvent)
		return errs.Wrap(err, "failed to load billings owners")
	}

	outgoing := make([]*hydroV0.AbuseDetectionEvent, 0, len(ownersByEntityID))
	for entityID, owner := range ownersByEntityID {
		tenantID, ok := dbEntities.EntityIDsToTenantIDs[entityID]
		if !ok {
			s.cfg.Log.Error(ctx, "result returned unexpected entity ID", kvp.String("gh.launch.entity.global_id", entityID.String()))
			continue
		}

		msg, ok := incomingByTenantName[tenantID]
		if !ok {
			s.cfg.Log.Error(ctx, "unexpectedly failed to find incoming message for tenant", kvp.String("gh.actions.tenant.id", tenantID))
			continue
		}

		msg.BillingPlanOwner = owner
		msg.BillingPlanOwner.TenantName = tenantID

		outgoing = append(outgoing, msg)
	}

	s.cfg.Hydro.Emit(abuseDetectionEventChange{outgoing})

	return nil
}

type metrics struct {
	TenantName                        string
	Score                             uint32
	MaxParallelism                    uint32
	FirstBuildDate                    time.Time
	TotalJobs                         uint32
	InProgressJobs                    uint32
	NumberOfLongRunningRequests       uint32
	AccountLifetimeInMinutes          uint32
	TotalJobRuntime                   uint32
	InProgressJobRuntime              uint32
	HasMaxConcurrentLongRunningBuilds bool
}

func (s *service) parseIncomingAbuseMetrics(ctx context.Context, jsonBody []byte) (map[string]*hydroV0.AbuseDetectionEvent, []string, error) {
	var parsed struct {
		AbuseMetrics []metrics `json:"abuseMetrics"`
	}
	if err := json.Unmarshal(jsonBody, &parsed); err != nil {
		return nil, nil, errs.Wrap(err, "error decoding payload for AbuseDetectionEvent")
	}
	metrics := parsed.AbuseMetrics

	incomingByTenantName := make(map[string]*hydroV0.AbuseDetectionEvent, len(metrics))
	tenantIDs := make([]string, 0, len(metrics))
	var hydroError error
	for _, m := range metrics {
		msg, err := updateAbuseMetricsToHydro(m)
		if err != nil {
			hydroError = err
			continue
		}

		incomingByTenantName[m.TenantName] = msg
		tenantIDs = append(tenantIDs, m.TenantName)
	}
	if hydroError != nil {
		s.cfg.Log.Report(ctx, errs.Wrap(hydroError, "one or more invalid abuse messages receivied"))
	}

	return incomingByTenantName, tenantIDs, nil
}

func updateAbuseMetricsToHydro(m metrics) (*hydroV0.AbuseDetectionEvent, error) {
	msg := &hydroV0.AbuseDetectionEvent{
		ReputationScore:                   m.Score,
		MaxParallelism:                    m.MaxParallelism,
		TotalJobs:                         m.TotalJobs,
		InProgressJobs:                    m.InProgressJobs,
		NumberOfLongRunningRequests:       m.NumberOfLongRunningRequests,
		AccountLifetimeInMinutes:          m.AccountLifetimeInMinutes,
		TotalJobRuntime:                   m.TotalJobRuntime,
		InProgressJobRuntime:              m.InProgressJobRuntime,
		HasMaxConcurrentLongRunningBuilds: m.HasMaxConcurrentLongRunningBuilds,
	}

	if m.FirstBuildDate.IsZero() {
		return nil, errs.New("FirstBuildDate must be non-zero value")
	}
	msg.FirstBuildDate = timestamppb.New(m.FirstBuildDate)

	return msg, nil
}

type abuseDetectionEventChange struct {
	changes []*hydroV0.AbuseDetectionEvent
}

func (a abuseDetectionEventChange) GetHydroMessages() []proto.Message {
	msgs := make([]proto.Message, 0, len(a.changes))
	for _, change := range a.changes {
		msgs = append(msgs, change)
	}
	return msgs
}

func (a abuseDetectionEventChange) GetEventType() string {
	return events.AbuseDetectionStatusEvent
}
