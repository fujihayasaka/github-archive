// Package eventhandlers contains the logic for handling Hydro events via hydro or aqueduct bridge
package eventhandlers

import (
	"context"
	"fmt"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	schemas "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	enterprise_accountv0 "github.com/github/hydro-schemas-go/hydro/schemas/github/enterprise_account/v0"
	licensingv0 "github.com/github/hydro-schemas-go/hydro/schemas/github/licensing/v0"
	ghrepositoriesv1 "github.com/github/hydro-schemas-go/hydro/schemas/github/repositories/v1"
	repositoriesv2 "github.com/github/hydro-schemas-go/hydro/schemas/github/repositories/v2"
	security_centerv0 "github.com/github/hydro-schemas-go/hydro/schemas/github/security_center/v0"
	githubv1 "github.com/github/hydro-schemas-go/hydro/schemas/github/v1"
	"github.com/github/licensify/internal/aqueduct/jobs"
	"github.com/github/licensify/internal/cosmos"
	"github.com/github/licensify/internal/engines"
	"github.com/github/licensify/internal/monolith"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/trace"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/anypb"
)

var (
	statKey = "event_handler.handle_raw.count"
)

// EventHandler is a struct that contains all the needed engines and clients to handle Hydro events.
type EventHandler struct {
	statter                 stats.Client
	tracer                  trace.Tracer
	jobby                   *jobs.Jobby
	monolithClient          *monolith.Client
	productEnablementEngine *engines.ProductEnablementEngine
	customerEngine          *engines.CustomerEngine
	customerLicenseEngine   *engines.CustomerLicenseEngine
	licenseeLicenseEngine   *engines.LicenseeLicenseEngine
}

// NewEventHandler creates a new EventHandler with all the needed engines and clients.
func NewEventHandler(dbConnection cosmos.ReadWriter, jobby *jobs.Jobby, monolithClient *monolith.Client, statter stats.Client, tracer trace.Tracer) (*EventHandler, error) {
	productEnablementEngine := engines.NewProductEnablementEngine(statter, tracer, dbConnection)
	customerEngine := engines.NewCustomerEngine(statter, tracer, dbConnection)
	customerLicenseEngine := engines.NewCustomerLicenseEngine(statter, tracer, dbConnection)
	licenseeLicenseEngine := engines.NewLicenseeLicenseEngine(statter, tracer, dbConnection)

	return &EventHandler{
		statter:                 statter,
		tracer:                  tracer,
		jobby:                   jobby,
		monolithClient:          monolithClient,
		productEnablementEngine: productEnablementEngine,
		customerEngine:          customerEngine,
		customerLicenseEngine:   customerLicenseEngine,
		licenseeLicenseEngine:   licenseeLicenseEngine,
	}, nil
}

// HandleRaw handles a raw Hydro envelope by Unmarshalling and delegating to the appropriate handler
func (eh *EventHandler) HandleRaw(ctx context.Context, logger log.Logger, rawEnvelope []byte, topic string) error {
	ctx, sp := eh.tracer.Start(ctx, "EventHandler.HandleRaw")
	defer sp.End()

	var envelope schemas.Envelope
	if err := proto.Unmarshal(rawEnvelope, &envelope); err != nil {
		logger.WithError(err).Error("Failed to unmarshal envelope")
		return fmt.Errorf("failed to unmarshal envelope: %w", err)
	}

	message, err := UnmarshalEnvelope(&envelope, logger)
	if err != nil {
		return err
	}

	var success Success
	var skip Skip
	var herr Error

	messageName := getSchemaName(message)
	logger.Info("Message received")
	sp.SetAttributes(attribute.KeyValue{Key: "message", Value: attribute.StringValue(messageName)})

	switch message := message.(type) {
	case *enterprise_accountv0.OrganizationAdd:
		skip, herr = eh.HandleOrganizationAdded(ctx, logger, message)
	case *enterprise_accountv0.OrganizationRemove:
		skip, herr = eh.HandleOrganizationRemoved(ctx, logger, message)
	case *enterprise_accountv0.OrganizationTransfer:
		skip, herr = eh.HandleOrganizationTransferred(ctx, logger, message)
	case *enterprise_accountv0.OrganizationUpgrade:
		skip, herr = eh.HandleOrganizationUpgraded(ctx, logger, message)
	case *security_centerv0.AdvancedSecurityToggled:
		skip, herr = eh.HandleAdvancedSecurityToggled(ctx, logger, message, &envelope)
	case *githubv1.BillingPlanChange:
		skip, herr = eh.HandleBillingPlanChanged(ctx, logger, message)
	case *githubv1.MembershipUpdate:
		success, skip, herr = eh.HandleMembershipUpdate(ctx, logger, message)
	case *githubv1.OrganizationSoftDelete:
		skip, herr = eh.HandleOrganizationSoftDelete(ctx, logger, message)
	case *githubv1.OrganizationRestore:
		skip, herr = eh.HandleOrganizationRestore(ctx, logger, message)
	case *githubv1.UserDestroy:
		skip, herr = eh.HandleUserDestroy(ctx, logger, message)
	case *githubv1.RepositoryAddMember:
		skip, herr = eh.HandleRepositoryAddMember(ctx, logger, message)
	case *ghrepositoriesv1.Deleted:
		skip, herr = eh.HandleRepositoryDeleted(ctx, logger, message)
	case *ghrepositoriesv1.VisibilityChanged:
		skip, herr = eh.HandleRepoVisibilityChanged(ctx, logger, message)
	case *repositoriesv2.Restored:
		skip, herr = eh.HandleRepositoryRestored(ctx, logger, message)
	case *licensingv0.EnterpriseManagedIdentitySuspended:
		skip, herr = eh.HandleEnterpriseManagedIdentitySuspended(ctx, logger, message)
	case *licensingv0.EnterpriseManagedIdentityUnsuspended:
		skip, herr = eh.HandleEnterpriseManagedIdentityUnsuspended(ctx, logger, message)
	default:
		return fmt.Errorf("no handler for message type %T", message)
	}

	logger.Info("Message handler finished")

	if herr.Err != nil {
		eh.trackError(logger, herr, messageName)
		return herr.Err
	}

	tags := stats.Tags{"message": messageName}
	var logMessage string
	if !skip.IsEmpty() {
		tags = tags.Merge(skip.Tags())
		logMessage = fmt.Sprintf("%s, skipping", skip.reason)
	} else {
		tags = tags.Merge(success.Tags())
		logMessage = fmt.Sprintf("Successfully processed %s message", messageName)
	}

	logger.Info(logMessage)
	eh.statter.Counter(statKey, tags, int64(1))

	return nil
}

// trackError tracks an error and logs it
func (eh *EventHandler) trackError(logger log.Logger, herr Error, messageName string) {
	eh.statter.Counter(statKey,
		herr.Tags().Merge(stats.Tags{"message": messageName}),
		int64(1),
	)
	logger.WithError(herr.Err).Error(fmt.Sprintf("error processing %s message", messageName))
	herr.span.RecordError(herr.Err)
	herr.span.SetStatus(codes.Error, herr.Origin())
}

// UnmarshalEnvelope uses the global proto registry to unmarshal an enveloped message via the Envelope's TypeURL
func UnmarshalEnvelope(envelope *schemas.Envelope, logger log.Logger) (proto.Message, error) {
	anyMessage := anypb.Any{
		TypeUrl: envelope.TypeUrl,
		Value:   envelope.Message,
	}
	message, err := anyMessage.UnmarshalNew()
	if err != nil {
		logger.WithError(err).Error("failed to unmarshal enveloped message")
		return message, fmt.Errorf("failed to unmarshal enveloped message: %w", err)
	}

	return message, nil
}
