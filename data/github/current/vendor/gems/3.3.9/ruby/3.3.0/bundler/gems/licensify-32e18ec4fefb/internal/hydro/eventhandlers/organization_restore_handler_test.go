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

type organizationRestoreTestSuite struct {
	suite.Suite
	mockDB             *mocks.MockDBReadWriter
	mockAqueductClient *mocks.MockAqueductClient
	handler            *eventhandlers.EventHandler
	cfg                *config.Config
}

func (s *organizationRestoreTestSuite) SetupTest() {
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

func (s *organizationRestoreTestSuite) TestOrganizationRestore() {
	jobID := "jobID-1234"
	logger := log.NewNullLogger()

	msg := stubs.NewOrganizationRestoreHydroMsg()

	syncJob := models.NewOrganizationSyncJob(msg.GetOrganization().GetId())
	wantPayload, err := json.Marshal(syncJob)
	s.Require().NoError(err)

	s.mockAqueductClient.On(
		"Send",
		mock.Anything,
		mock.MatchedBy(func(j aqueduct.Job) bool {
			return j.App == s.cfg.AqueductApp &&
				j.Queue == queues.QueueSyncOrgMemberships &&
				j.Headers[jobs.JobNameHeader] == jobs.JobNameSyncOrgMemberships &&
				bytes.Equal(j.Payload, wantPayload)
		}),
		mock.AnythingOfType("[]aqueduct.SendOption"),
	).Return(jobID, nil).Once()

	_, herr := s.handler.HandleOrganizationRestore(context.Background(), logger, msg)
	s.Require().NoError(herr.Err)

	s.mockAqueductClient.AssertExpectations(s.T())
}

func TestOrganizationRestoreSuite(t *testing.T) {
	suite.Run(t, new(organizationRestoreTestSuite))
}
