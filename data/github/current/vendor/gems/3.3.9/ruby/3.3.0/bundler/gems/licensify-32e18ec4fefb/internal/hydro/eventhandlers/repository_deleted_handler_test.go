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
	repositoriesv1 "github.com/github/licensify/lib/monolith-twirp/repositories/v1"
	"github.com/github/licensify/testing/mocks"
	"github.com/github/licensify/testing/stubs"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"
)

type repositoryDeletedHandlerTestSuite struct {
	suite.Suite
	cfg                *config.Config
	handler            *eventhandlers.EventHandler
	mockMonolithAPI    *mocks.MockMonolithAPI
	mockAqueductClient *mocks.MockAqueductClient
	logger             log.Logger
}

func (s *repositoryDeletedHandlerTestSuite) SetupTest() {
	cfg, _ := config.Load()
	statter := cfg.StatsClient()
	telem, _ := telemetry.NewFromEnv()
	tracer := telem.Tracer.Tracer

	s.cfg = cfg
	s.mockMonolithAPI = &mocks.MockMonolithAPI{}
	s.mockAqueductClient = &mocks.MockAqueductClient{}
	s.logger = log.NewNullLogger()
	monolithClient := &monolith.Client{RepositoriesAPI: s.mockMonolithAPI}
	jobby := &jobs.Jobby{Cfg: cfg, AqueductClient: s.mockAqueductClient}

	eventHandler, _ := eventhandlers.NewEventHandler(&mocks.MockDBReadWriter{}, jobby, monolithClient, statter, tracer)
	s.handler = eventHandler
}

func (s *repositoryDeletedHandlerTestSuite) TestProcessMessageQueuesDeleteEnablementJob() {
	customerID := stubs.NewRandomID()

	msg := stubs.NewRepositoryDeletedHydroMsg()

	repoReq := &repositoriesv1.GetRepositoryInformationRequest{Id: uint64(msg.GetRepositoryId())}
	repoRes := &repositoriesv1.GetRepositoryInformationResponse{Repository: &repositoriesv1.Repository{
		Id:              uint64(msg.GetRepositoryId()),
		OwnerCustomerId: int64(customerID),
	}}
	s.mockMonolithAPI.On(
		"GetRepositoryInformation",
		mock.Anything,
		repoReq,
	).Return(repoRes, nil).Once()

	wantPayload, err := json.Marshal(&models.DeleteEnablementsJob{
		CustomerID:       customerID,
		EnablementReason: models.EnablementReasonRepositoryCollaborator,
		EnablementID:     uint64(msg.GetRepositoryId()),
	})
	s.Require().NoError(err)

	s.mockAqueductClient.On(
		"Send",
		mock.Anything,
		mock.MatchedBy(func(j aqueduct.Job) bool {
			return j.App == s.cfg.AqueductApp &&
				j.Queue == queues.QueueDeleteEnablements &&
				j.Headers[jobs.JobNameHeader] == jobs.JobNameDeleteEnablements &&
				bytes.Equal(j.Payload, wantPayload)
		}),
		mock.AnythingOfType("[]aqueduct.SendOption"),
	).Return("job-id", nil).Once()

	_, herr := s.handler.HandleRepositoryDeleted(context.Background(), s.logger, msg)
	s.Require().NoError(herr.Err)
}

func (s *repositoryDeletedHandlerTestSuite) TestProcessMessageSkipsMissingCustomerID() {
	msg := stubs.NewRepositoryDeletedHydroMsg()

	repoReq := &repositoriesv1.GetRepositoryInformationRequest{Id: uint64(msg.GetRepositoryId())}
	repoRes := &repositoriesv1.GetRepositoryInformationResponse{Repository: &repositoriesv1.Repository{
		Id: uint64(msg.GetRepositoryId()),
	}}
	s.mockMonolithAPI.On(
		"GetRepositoryInformation",
		mock.Anything,
		repoReq,
	).Return(repoRes, nil).Once()

	_, herr := s.handler.HandleRepositoryDeleted(context.Background(), s.logger, msg)
	s.Require().NoError(herr.Err)
	s.mockAqueductClient.AssertNotCalled(s.T(), "Send", mock.Anything, mock.Anything)
}

func TestRepositoryDeletedHandlerTestSuite(t *testing.T) {
	suite.Run(t, new(repositoryDeletedHandlerTestSuite))
}
