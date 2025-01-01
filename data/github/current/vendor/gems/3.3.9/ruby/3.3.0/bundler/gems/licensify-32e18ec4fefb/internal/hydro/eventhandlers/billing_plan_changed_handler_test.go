package eventhandlers_test

import (
	"bytes"
	"context"
	"encoding/json"
	"testing"

	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/github-telemetry-go/telemetry"
	githubv1 "github.com/github/hydro-schemas-go/hydro/schemas/github/v1"
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

type billingPlanChangedTestSuite struct {
	suite.Suite
	mockDB             *mocks.MockDBReadWriter
	mockAqueductClient *mocks.MockAqueductClient
	handler            *eventhandlers.EventHandler
	cfg                *config.Config
}

func (s *billingPlanChangedTestSuite) SetupTest() {
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

func (s *billingPlanChangedTestSuite) TestOrganizationTeamUpgradeIgnoresActionNotUpgraded() {
	tests := []struct {
		name         string
		action       githubv1.BillingPlanChange_Action
		previousPlan string
		currentPlan  string
	}{
		{
			name:         "downgrade",
			action:       githubv1.BillingPlanChange_DOWNGRADE,
			previousPlan: "business",
			currentPlan:  "free",
		},
		{
			name:         "upgrade from free to business_plus", // free to business_plus (Enterprise) is covered by OrganizationUpgrade so we ignore it here
			action:       githubv1.BillingPlanChange_UPGRADE,
			previousPlan: "free",
			currentPlan:  "business_plus",
		},
	}
	for _, tt := range tests {
		s.Run(tt.name, func() {
			logger := log.NewNullLogger()
			msg := stubs.NewBillingPlanChangeHydroMsg()
			msg.Action = tt.action
			msg.PreviousPlan = tt.previousPlan
			msg.CurrentPlan = tt.currentPlan

			skip, herr := s.handler.HandleBillingPlanChanged(context.Background(), logger, msg)
			s.Require().NoError(herr.Err)

			s.False(skip.IsEmpty())
			s.mockAqueductClient.AssertNotCalled(s.T(), "Send", mock.Anything, mock.Anything, mock.Anything, mock.Anything)
		})
	}
}

func (s *billingPlanChangedTestSuite) TestOrganizationTeamUpgradeQueuesSyncJobs() {
	jobID := "jobID-1234"
	logger := log.NewNullLogger()
	msg := stubs.NewBillingPlanChangeHydroMsg()

	syncJob := models.NewOrganizationSyncJob(msg.Organization.GetId())
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

	_, herr := s.handler.HandleBillingPlanChanged(context.Background(), logger, msg)
	s.Require().NoError(herr.Err)

	s.mockAqueductClient.AssertExpectations(s.T())
}

func TestBillingPlanChangedSuite(t *testing.T) {
	suite.Run(t, new(billingPlanChangedTestSuite))
}
