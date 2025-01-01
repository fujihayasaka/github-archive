package eventhandlers_test

import (
	"bytes"
	"context"
	"encoding/json"
	"testing"

	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/licensify/internal/aqueduct/jobs"
	"github.com/github/licensify/internal/aqueduct/queues"
	"github.com/github/licensify/internal/config"
	"github.com/github/licensify/internal/hydro/eventhandlers"
	"github.com/github/licensify/internal/models"
	"github.com/github/licensify/internal/monolith"
	"github.com/github/licensify/testing/mocks"
	"github.com/github/licensify/testing/stubs"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"
)

type organizationTransferredTestSuite struct {
	suite.Suite
	mockDB             *mocks.MockDBReadWriter
	mockAqueductClient *mocks.MockAqueductClient
	handler            *eventhandlers.EventHandler
	cfg                *config.Config
}

func (s *organizationTransferredTestSuite) SetupTest() {
	s.cfg, _ = config.Load()
	statter := s.cfg.StatsClient()
	telem, _ := telemetry.NewFromEnv()
	tracer := telem.Tracer.Tracer

	s.mockDB = &mocks.MockDBReadWriter{}
	s.mockAqueductClient = &mocks.MockAqueductClient{}
	jobby := &jobs.Jobby{Cfg: s.cfg, AqueductClient: s.mockAqueductClient}

	handler, _ := eventhandlers.NewEventHandler(s.mockDB, jobby, &monolith.Client{}, statter, tracer)
	s.handler = handler
}

func (s *organizationTransferredTestSuite) TestOrganizationStateChangeTransfer() {
	jobID := "jobID-1234"
	logger := log.NewNullLogger()

	msg := stubs.NewOrganizationTransferHydroMsg()

	syncJob1 := models.NewCustomerSyncJob(uint64(msg.GetSourceEnterprise().GetCustomerId()))
	wantPayload1, err := json.Marshal(syncJob1)
	s.Require().NoError(err)

	syncJob2 := models.NewCustomerSyncJob(uint64(msg.GetDestinationEnterprise().GetCustomerId()))
	wantPayload2, err := json.Marshal(syncJob2)
	s.Require().NoError(err)

	var wantPayloads [][]byte
	s.mockAqueductClient.On(
		"Send",
		mock.Anything,
		mock.MatchedBy(func(j aqueduct.Job) bool {
			// used to compare order & completeness of payloads sent below
			wantPayloads = append(wantPayloads, j.Payload)

			correctConfig := j.App == s.cfg.AqueductApp &&
				j.Queue == queues.QueueSyncOrgMemberships &&
				j.Headers[jobs.JobNameHeader] == jobs.JobNameSyncOrgMemberships
			matchingJobsToPayloads := (bytes.Equal(j.Payload, wantPayload1) || bytes.Equal(j.Payload, wantPayload2))

			return correctConfig && matchingJobsToPayloads
		}),
		mock.AnythingOfType("[]aqueduct.SendOption"),
	).Return(jobID, nil).Twice()

	_, herr := s.handler.HandleOrganizationTransferred(context.Background(), logger, msg)
	s.Require().NoError(herr.Err)

	s.Equal(wantPayloads, [][]byte{wantPayload1, wantPayload2})
	s.mockAqueductClient.AssertExpectations(s.T())
}

func TestOrganizationTransferredSuite(t *testing.T) {
	suite.Run(t, new(organizationTransferredTestSuite))
}
