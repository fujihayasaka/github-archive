package transitions

import (
	"bytes"
	"context"
	"encoding/json"
	"testing"

	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/licensify/internal/aqueduct/jobs"
	"github.com/github/licensify/internal/aqueduct/queues"
	"github.com/github/licensify/internal/config"
	"github.com/github/licensify/internal/models"
	"github.com/github/licensify/testing/mocks"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"
)

type addLicenseStatusTransitionSuite struct {
	suite.Suite
	cfg                *config.Config
	mockAqueductClient *mocks.MockAqueductClient
	transition         *AddLicenseStatusTransition
}

func (s *addLicenseStatusTransitionSuite) SetupTest() {
	logger := log.NewNullLogger()
	cfg, _ := config.Load()
	s.cfg = cfg
	s.mockAqueductClient = &mocks.MockAqueductClient{}
	s.transition = NewAddLicenseStatusTransition(cfg, logger, s.mockAqueductClient)
}

func (s *addLicenseStatusTransitionSuite) TestTransitionDoesNotQueueJobInDryRunMode() {
	customerID := uint64(1)
	ctx := context.Background()

	s.Require().NoError(s.transition.Run(ctx, customerID, customerID, true))
	s.mockAqueductClient.AssertNotCalled(s.T(), "Send", mock.Anything, mock.Anything, mock.Anything)
}

func (s *addLicenseStatusTransitionSuite) TestTransitionPatchesLicenseStatus() {
	startID := uint64(1)
	endID := uint64(3)
	ctx := context.Background()

	for i := startID; i <= endID; i++ {
		wantPayload, err := json.Marshal(&models.BackfillLicenseStatusJob{CustomerID: i})
		s.Require().NoError(err)
		s.mockAqueductClient.On(
			"Send",
			mock.Anything,
			mock.MatchedBy(func(j aqueduct.Job) bool {
				return j.App == s.cfg.AqueductApp &&
					j.Queue == queues.QueueBackfillLicenseStatus &&
					j.Headers[jobs.JobNameHeader] == jobs.JobNameBackfillLicenseStatus &&
					bytes.Equal(j.Payload, wantPayload)
			}),
			[]aqueduct.SendOption(nil),
		).Return("job-id", nil).Once()
	}

	s.Require().NoError(s.transition.Run(ctx, startID, endID, false))
	s.mockAqueductClient.AssertExpectations(s.T())
}

func TestAddLicenseStatusTransitionSuite(t *testing.T) {
	suite.Run(t, new(addLicenseStatusTransitionSuite))
}
