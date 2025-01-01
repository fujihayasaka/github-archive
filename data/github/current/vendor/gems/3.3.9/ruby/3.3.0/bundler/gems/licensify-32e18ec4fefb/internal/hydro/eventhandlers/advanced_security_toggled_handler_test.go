package eventhandlers_test

import (
	"context"
	"encoding/json"
	"fmt"
	"testing"

	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/github-telemetry-go/telemetry"

	security_centerv0 "github.com/github/hydro-schemas-go/hydro/schemas/github/security_center/v0"
	"github.com/github/licensify/internal/aqueduct/jobs"
	"github.com/github/licensify/internal/config"
	"github.com/github/licensify/internal/hydro/eventhandlers"
	"github.com/github/licensify/internal/models"
	"github.com/github/licensify/internal/monolith"
	"github.com/github/licensify/testing/helpers"
	"github.com/github/licensify/testing/mocks"
	"github.com/github/licensify/testing/stubs"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
)

func TestHandleEnvelopeCreatesProductEnablement(t *testing.T) {
	cfg, _ := config.Load()
	statter := cfg.StatsClient()
	logger := log.NewNullLogger()
	telem, _ := telemetry.NewFromEnv()
	tracer := telem.Tracer.Tracer

	mockDB := &mocks.MockDBReadWriter{}
	jobby := &jobs.Jobby{Cfg: cfg, AqueductClient: &mocks.MockAqueductClient{}}

	peProto := stubs.NewProductEnablementProto()
	wantPk := azcosmos.NewPartitionKeyString(fmt.Sprintf("%d/%s", peProto.CustomerId, "ProductEnablement"))
	wantMarshalled, err := json.Marshal(models.NewProductEnablementFromProto(peProto))
	require.NoError(t, err)

	mockDB.On(
		"UpsertItem",
		mock.Anything,
		wantPk,
		wantMarshalled,
		mock.Anything,
	).Return(azcosmos.ItemResponse{}, nil).Once()

	handler, _ := eventhandlers.NewEventHandler(mockDB, jobby, &monolith.Client{}, statter, tracer)

	msg := &security_centerv0.AdvancedSecurityToggled{
		CustomerId:     int64(peProto.CustomerId),
		RepositoryId:   int64(peProto.EnablementId),
		FeatureEnabled: true,
	}
	envelope := helpers.NewEnvelopeFromProtoMessage(t, msg)

	_, herr := handler.HandleAdvancedSecurityToggled(context.Background(), logger, msg, envelope)
	require.NoError(t, herr.Err)
	mockDB.AssertExpectations(t)
}

func TestHandleEnvelopMissingCustomerID(t *testing.T) {
	cfg, _ := config.Load()
	statter := cfg.StatsClient()
	logger := log.NewNullLogger()
	telem, _ := telemetry.NewFromEnv()
	tracer := telem.Tracer.Tracer

	mockDB := &mocks.MockDBReadWriter{}
	jobby := &jobs.Jobby{Cfg: cfg, AqueductClient: &mocks.MockAqueductClient{}}

	handler, _ := eventhandlers.NewEventHandler(mockDB, jobby, &monolith.Client{}, statter, tracer)

	msg := &security_centerv0.AdvancedSecurityToggled{
		RepositoryId:   123,
		FeatureEnabled: true,
	}
	envelope := helpers.NewEnvelopeFromProtoMessage(t, msg)

	_, herr := handler.HandleAdvancedSecurityToggled(context.Background(), logger, msg, envelope)
	require.NoError(t, herr.Err)

	mockDB.AssertNotCalled(t, "UpsertItem", mock.Anything, mock.Anything, mock.Anything, mock.Anything)
}
