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

type repositoryRestoredTestSuite struct {
	suite.Suite
	cfg                *config.Config
	mockAqueductClient *mocks.MockAqueductClient
	handler            *eventhandlers.EventHandler
	logger             log.Logger
}

func (s *repositoryRestoredTestSuite) SetupTest() {
	s.cfg, _ = config.Load()
	statter := s.cfg.StatsClient()
	telem, _ := telemetry.NewFromEnv()
	tracer := telem.Tracer.Tracer

	s.mockAqueductClient = &mocks.MockAqueductClient{}
	s.logger = log.NewNullLogger()
	jobby := &jobs.Jobby{Cfg: s.cfg, AqueductClient: s.mockAqueductClient}

	handler, _ := eventhandlers.NewEventHandler(&mocks.MockDBReadWriter{}, jobby, &monolith.Client{}, statter, tracer)
	s.handler = handler
}

func (s *repositoryRestoredTestSuite) TestHandlerSkipsMissingRepositoryID() {
	msg := stubs.NewRepositoryRestoredHydroMsg()
	msg.RepositoryId = 0

	skip, herr := s.handler.HandleRepositoryRestored(context.Background(), s.logger, msg)
	s.Require().NoError(herr.Err)

	s.False(skip.IsEmpty())
}

func (s *repositoryRestoredTestSuite) TestHandlerEnqueuesCreateRepositoryCollaboratorsJob() {
	jobID := "jobID-1234"

	msg := stubs.NewRepositoryRestoredHydroMsg()

	wantPayload, err := json.Marshal(&models.CreateRepositoryCollaboratorsJob{
		RepositoryID: uint64(msg.GetRepositoryId()),
	})
	s.Require().NoError(err)

	s.mockAqueductClient.On(
		"Send",
		mock.Anything,
		mock.MatchedBy(func(j aqueduct.Job) bool {
			return j.App == s.cfg.AqueductApp &&
				j.Queue == queues.QueueCreateRepositoryCollaborators &&
				j.Headers[jobs.JobNameHeader] == jobs.JobNameCreateRepositoryCollaborators &&
				bytes.Equal(j.Payload, wantPayload)
		}),
		mock.AnythingOfType("[]aqueduct.SendOption"),
	).Return(jobID, nil).Once()

	_, herr := s.handler.HandleRepositoryRestored(context.Background(), s.logger, msg)
	s.Require().NoError(herr.Err)
}

func TestRepositoryRestoredHandlerSuite(t *testing.T) {
	suite.Run(t, new(repositoryRestoredTestSuite))
}
