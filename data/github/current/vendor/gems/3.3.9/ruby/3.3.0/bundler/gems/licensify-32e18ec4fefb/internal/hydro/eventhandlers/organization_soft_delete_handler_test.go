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

type organizationSoftDeleteTestSuite struct {
	suite.Suite
	cfg                *config.Config
	mockAqueductClient *mocks.MockAqueductClient
	handler            *eventhandlers.EventHandler
	logger             log.Logger
}

func (s *organizationSoftDeleteTestSuite) SetupTest() {
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

func (s *organizationSoftDeleteTestSuite) TestHandlerSkipsMessage() {
	tests := []struct {
		name           string
		organizationID uint64
		customerID     int64
	}{
		{
			name:           "missing customer ID",
			organizationID: 1,
			customerID:     0,
		},
		{
			name:           "skips unsupported context",
			organizationID: 0,
			customerID:     1,
		},
	}
	for _, tt := range tests {
		s.Run(tt.name, func() {
			msg := stubs.NewOrganizationSoftDeleteHydroMsg()

			msg.Organization.Id = tt.organizationID
			msg.CustomerId = tt.customerID

			skip, err := s.handler.HandleOrganizationSoftDelete(context.Background(), s.logger, msg)
			s.Require().NoError(err.Err)

			s.False(skip.IsEmpty())
			s.mockAqueductClient.AssertNotCalled(s.T(), "Send", mock.Anything, mock.Anything, mock.Anything)
		})
	}
}

func (s *organizationSoftDeleteTestSuite) TestHandlerEnqueuesDeleteEnablementsJob() {
	jobID := "jobID-1234"

	msg := stubs.NewOrganizationSoftDeleteHydroMsg()

	wantPayload, err := json.Marshal(&models.DeleteEnablementsJob{
		CustomerID:       uint64(msg.GetCustomerId()),
		EnablementReason: models.EnablementReasonOrgMembership,
		EnablementID:     msg.GetOrganization().GetId(),
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
	).Return(jobID, nil).Once()

	_, handlerError := s.handler.HandleOrganizationSoftDelete(context.Background(), s.logger, msg)
	s.Require().NoError(handlerError.Err)
}

func TestOrganizationSoftDeleteHandlerSuite(t *testing.T) {
	suite.Run(t, new(organizationSoftDeleteTestSuite))
}
