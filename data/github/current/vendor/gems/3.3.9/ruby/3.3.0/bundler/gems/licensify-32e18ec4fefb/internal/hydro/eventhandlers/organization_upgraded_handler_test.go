package eventhandlers_test

import (
	"bytes"
	"context"
	"encoding/json"
	"testing"

	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/github-telemetry-go/telemetry"
	enterprise_accountv0 "github.com/github/hydro-schemas-go/hydro/schemas/github/enterprise_account/v0"
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

type organizationUpgradedTestSuite struct {
	suite.Suite
	mockDB             *mocks.MockDBReadWriter
	mockAqueductClient *mocks.MockAqueductClient
	handler            *eventhandlers.EventHandler
	cfg                *config.Config
}

func (s *organizationUpgradedTestSuite) SetupTest() {
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

func (s *organizationUpgradedTestSuite) TestOrganizationUpgradeIgnoresStatusNotUpgraded() {
	tests := []struct {
		name          string
		upgradeStatus enterprise_accountv0.OrganizationUpgrade_UpgradeStatus
	}{
		{
			name:          "upgrade status UPGRADE_PURCHASE_INITIATED",
			upgradeStatus: enterprise_accountv0.OrganizationUpgrade_UPGRADE_PURCHASE_INITIATED,
		},
		{
			name:          "upgrade status UPGRADE_INITIATED",
			upgradeStatus: enterprise_accountv0.OrganizationUpgrade_UPGRADE_INITIATED,
		},
		{
			name:          "upgrade status UPGRADE_CANCELLED",
			upgradeStatus: enterprise_accountv0.OrganizationUpgrade_UPGRADE_CANCELLED,
		},
	}

	for _, tt := range tests {
		s.Run(tt.name, func() {
			logger := log.NewNullLogger()
			msg := stubs.NewOrganizationUpgradeHydroMsg()
			msg.Status = tt.upgradeStatus

			skip, herr := s.handler.HandleOrganizationUpgraded(context.Background(), logger, msg)
			s.Require().NoError(herr.Err)

			s.False(skip.IsEmpty())
			s.mockAqueductClient.AssertNotCalled(s.T(), "Send", mock.Anything, mock.Anything, mock.Anything, mock.Anything)
		})
	}
}

func (s *organizationUpgradedTestSuite) TestOrganizationUpgradeQueuesSyncJobs() {
	tests := []struct {
		name          string
		upgradeStatus enterprise_accountv0.OrganizationUpgrade_UpgradeStatus
	}{
		{
			name:          "upgrade status DIRECT_UPGRADED",
			upgradeStatus: enterprise_accountv0.OrganizationUpgrade_DIRECT_UPGRADED,
		},
		{
			name:          "upgrade status PURCHASE_UPGRADED",
			upgradeStatus: enterprise_accountv0.OrganizationUpgrade_PURCHASE_UPGRADED,
		},
	}

	for _, tt := range tests {
		s.Run(tt.name, func() {
			jobID := "jobID-1234"
			logger := log.NewNullLogger()
			msg := stubs.NewOrganizationUpgradeHydroMsg()
			msg.Status = tt.upgradeStatus

			syncJob1 := models.NewCustomerSyncJob(uint64(msg.GetOrganizationPreviousCustomerId()))
			wantPayload1, err := json.Marshal(syncJob1)
			s.Require().NoError(err)

			syncJob2 := models.NewCustomerSyncJob(uint64(msg.GetEnterprise().GetCustomerId()))
			wantPayload2, err := json.Marshal(syncJob2)
			s.Require().NoError(err)

			var wantPayloads [][]byte
			s.mockAqueductClient.On(
				"Send",
				mock.Anything,
				mock.MatchedBy(func(j aqueduct.Job) bool {
					wantPayloads = append(wantPayloads, j.Payload)

					correctConfig := j.App == s.cfg.AqueductApp &&
						j.Queue == queues.QueueSyncOrgMemberships &&
						j.Headers[jobs.JobNameHeader] == jobs.JobNameSyncOrgMemberships
					matchingJobsToPayloads := (bytes.Equal(j.Payload, wantPayload1) || bytes.Equal(j.Payload, wantPayload2))

					return correctConfig && matchingJobsToPayloads
				}),
				mock.AnythingOfType("[]aqueduct.SendOption"),
			).Return(jobID, nil).Twice()

			_, herr := s.handler.HandleOrganizationUpgraded(context.Background(), logger, msg)
			s.Require().NoError(herr.Err)

			s.Equal(wantPayloads, [][]byte{wantPayload1, wantPayload2})
			s.mockAqueductClient.AssertExpectations(s.T())
		})
	}
}

func TestOrganizationUpgradeduite(t *testing.T) {
	suite.Run(t, new(organizationUpgradedTestSuite))
}
