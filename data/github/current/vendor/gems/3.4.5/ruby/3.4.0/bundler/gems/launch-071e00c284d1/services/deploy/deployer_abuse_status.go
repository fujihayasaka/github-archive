package deploy

import (
	"bytes"
	"context"
	"encoding/json"
	"time"

	// nolint:staticcheck
	"github.com/golang/protobuf/proto"
	errs "github.com/pkg/errors"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/github/go-kvp"

	"github.com/github/launch/auth"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/hydro/events"
	hydroV0 "github.com/github/launch/hydro/schemas/github/actions/v0"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/services/errors"
	pb "github.com/github/launch/services/pb/deploy"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/graphqlid"
)

const (
	primaryHMACKeyName   = "ActionsAuthHmacKeyPrimary"
	secondaryHMACKeyName = "ActionsAuthHmacKeySecondary"
)

func (s *service) AbuseStatus(ctx context.Context, req *pb.AbuseStatusRequest) (*pb.AbuseStatusResponse, error) {
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
		s.cfg.Log.Error(ctx, "error validating signature for abuse status")
		return res, nil
	}

	if err := s.perform(ctx, req); err != nil {
		s.cfg.Log.Report(ctx, err)
		span.RecordError(err)
		return res, errors.NewInternalError(err.Error())
	}

	return res, nil
}

func (s *service) perform(ctx context.Context, req *pb.AbuseStatusRequest) error {
	incomingByTenantName, tenantIDs, err := s.parseIncoming(ctx, req.Status)
	if err != nil {
		s.cfg.Hydro.CountErroredEvent(events.ReputationScoreChangeEvent)
		return err
	}

	if len(tenantIDs) == 0 {
		// nothing to do
		return nil
	}

	dbEntities, err := s.cfg.AZPResources.GetDataForAbuseHydro(ctx, tenantIDs)
	if err != nil {
		s.cfg.Hydro.CountErroredEvent(events.ReputationScoreChangeEvent)
		return errs.Wrap(err, "failed to retrieve tenants from DB")
	}
	entityIDs := mapEntityIDs(dbEntities)

	s.countIncomingEntityTypes(ctx, entityIDs)

	ownersByEntityID, err := s.getBillingOwnersFromDotcom(ctx, entityIDs)
	if err != nil {
		s.cfg.Hydro.CountErroredEvent(events.ReputationScoreChangeEvent)
		return errs.Wrap(err, "failed to load billings owners")
	}

	outgoing := make([]*hydroV0.ReputationScoreChange, 0, len(ownersByEntityID))
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

	s.cfg.Hydro.Emit(reputationScoreEvent{outgoing})

	return nil
}

type update struct {
	TenantName              string
	Score                   uint32
	IsConstant              bool
	FirstDate               time.Time
	EvaluationDate          time.Time
	HasPrivateProject       bool
	MaxParallelism          uint32
	RunCount                uint32
	RunAverage              uint32
	RunDeviation            uint32
	RunDensity              uint32
	MaliciousProcessDensity uint32
	AlteredHostsFileDensity uint32
	SuspiciousSourceDensity uint32
}

func (s *service) getBillingOwnersFromDotcom(ctx context.Context, entityIDs []types.GlobalID) (map[types.GlobalID]*hydroV0.BillingPlanOwner, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	internalClient, err := s.cfg.InternalClientFactory.Create()
	if err != nil {
		return nil, tracing.RecordError(span, err)
	}
	ownersByEntities, err := internalClient.GetAbuseDataForHydro(ctx, entityIDs)
	if err != nil {
		return nil, tracing.RecordError(span, err)
	}
	return ownersByEntities.OwnersByEntityID, nil
}

func mapEntityIDs(dbEntities *deployer.AbuseHydroDBData) []types.GlobalID {
	entityIDs := make([]types.GlobalID, 0, len(dbEntities.EntityIDsToTenantIDs))
	for entityID := range dbEntities.EntityIDsToTenantIDs {
		entityIDs = append(entityIDs, entityID)
	}
	return entityIDs
}

func (s *service) parseIncoming(ctx context.Context, jsonBody []byte) (map[string]*hydroV0.ReputationScoreChange, []string, error) {
	var parsed struct {
		Reputations []update `json:"reputations"`
	}
	if err := json.Unmarshal(jsonBody, &parsed); err != nil {
		return nil, nil, errs.Wrap(err, "error decoding payload for ActorReputationScoreChange")
	}
	updates := parsed.Reputations

	incomingByTenantName := make(map[string]*hydroV0.ReputationScoreChange, len(updates))
	tenantIDs := make([]string, 0, len(updates))
	var hydroError error
	for _, up := range updates {
		msg, err := updateToHydro(up)
		if err != nil {
			hydroError = err
			continue
		}

		incomingByTenantName[up.TenantName] = msg
		tenantIDs = append(tenantIDs, up.TenantName)
	}
	if hydroError != nil {
		s.cfg.Log.Report(ctx, errs.Wrap(hydroError, "one or more invalid abuse messages recevied"))
	}

	return incomingByTenantName, tenantIDs, nil
}

func updateToHydro(up update) (*hydroV0.ReputationScoreChange, error) {
	msg := &hydroV0.ReputationScoreChange{
		ReputationScore:         up.Score,
		IsConstant:              up.IsConstant,
		HasPrivateProject:       up.HasPrivateProject,
		MaxParallelism:          up.MaxParallelism,
		RunCount:                up.RunCount,
		RunAverage:              up.RunAverage,
		RunDeviation:            up.RunDeviation,
		RunDensity:              up.RunDensity,
		MaliciousProcessDensity: up.MaliciousProcessDensity,
		AlteredHostsFileDensity: up.AlteredHostsFileDensity,
		SuspiciousSourceDensity: up.SuspiciousSourceDensity,
	}

	if up.FirstDate.IsZero() {
		return nil, errs.New("FirstDate must be non-zero value")
	}
	msg.FirstDate = timestamppb.New(up.FirstDate)

	if up.EvaluationDate.IsZero() {
		return nil, errs.New("EvaluationDate must be non-zero value")
	}
	msg.EvaluationDate = timestamppb.New(up.EvaluationDate)

	return msg, nil
}

func (s *service) countIncomingEntityTypes(ctx context.Context, ids []types.GlobalID) {
	counts := sumByEntityType(ids)
	for typeName, count := range counts {
		s.cfg.Stats.Counter(ctx, "abuse_status_tenant_type", statter.Tags{
			"tenant_type": typeName,
		}, count)
	}
}

func sumByEntityType(ids []types.GlobalID) map[string]int64 {
	counts := make(map[string]int64)
	for _, id := range ids {
		typeName, _, err := graphqlid.Decode(id.String())
		if err == nil {
			counts[typeName]++
		}
	}
	return counts
}

type reputationScoreEvent struct {
	changes []*hydroV0.ReputationScoreChange
}

func (r reputationScoreEvent) GetHydroMessages() []proto.Message {
	msgs := make([]proto.Message, 0, len(r.changes))
	for _, change := range r.changes {
		msgs = append(msgs, change)
	}
	return msgs
}

func (r reputationScoreEvent) GetEventType() string {
	return events.ReputationScoreChangeEvent
}

type keyVaultAuthVal struct {
	Password []byte `json:"Password"`
}

func (s *service) verifySignature(ctx context.Context, req *pb.AbuseStatusRequest) (bool, error) {
	// build message
	getMessage := func(req *pb.AbuseStatusRequest) []byte {
		var msg bytes.Buffer
		_, _ = msg.Write([]byte(req.RequestURI))
		_, _ = msg.Write([]byte("\n"))
		_, _ = msg.Write(req.Status)
		return msg.Bytes()
	}

	vaultName := s.cfg.AzureProviderConfig.AuthVaultName

	secret1, err := s.cfg.KeyVaultClient.GetSecret(ctx, vaultName, primaryHMACKeyName)
	if err != nil {
		return false, errs.Wrap(err, "failed to fetch primary hmac key")
	}
	var primaryKey keyVaultAuthVal
	if err := json.Unmarshal([]byte(secret1.Value), &primaryKey); err != nil {
		return false, errs.Wrap(err, "failed to decode primary hmac key")
	}

	secret2, err := s.cfg.KeyVaultClient.GetSecret(ctx, vaultName, secondaryHMACKeyName)
	if err != nil {
		return false, errs.Wrap(err, "failed to fetch secondary hmac key")
	}
	var secondaryKey keyVaultAuthVal
	if err := json.Unmarshal([]byte(secret2.Value), &secondaryKey); err != nil {
		return false, errs.Wrap(err, "failed to decode secondary  hmac key")
	}

	keys := []auth.Key{auth.NewKey(primaryKey.Password), auth.NewKey(secondaryKey.Password)}
	return s.cfg.Verifier.Verify(auth.NewSignature(req.Signature), getMessage(req), keys...), nil
}
