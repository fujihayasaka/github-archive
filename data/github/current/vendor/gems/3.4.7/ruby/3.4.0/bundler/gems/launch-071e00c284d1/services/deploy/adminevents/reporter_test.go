package adminevents

import (
	"context"
	"errors"
	"testing"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/observability"
	types "github.com/github/launch/types"
	"github.com/github/launch/utils/testutils"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"

	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/pkg/azp"
)

const (
	testOrg                  = "test-org"
	testRepo                 = "test-repo"
	testSpammyReason         = "test-reason"
	testRepositoryGlobalID   = types.GlobalID("R_lAHNJr8DAw")
	testBillingOwnerGlobalID = types.GlobalID("O_kgDNA-o")
)

func TestAdminEventsReporter(t *testing.T) {
	suite.Run(t, new(AdminEventsReporterSuite))
}

type AdminEventsReporterSuite struct {
	suite.Suite
	workflowBuildRepositoryMock *deployer.MockWorkflowBuildsRepository
	repositoryClientFactoryMock *azp.MockRepositoryClientFactory
	repositoryClientMock        *azp.MockRepositoryClient
	azpResourcesRepo            *deployer.MockAzpResourcesRepository
	ghTwirpClientMock           *ghtwirp.MockClient
	log                         testutils.RecordingLogger
	reporter                    Reporter
	orgMatcher                  func(types.GlobalID) bool
	repoMatcher                 func(types.GlobalID) bool
}

func (s *AdminEventsReporterSuite) SetupTest() {
	log := testutils.NewRecordingLogger()
	obs := observability.New(log.Logger, statter.NullStatter())
	s.azpResourcesRepo = &deployer.MockAzpResourcesRepository{}
	s.workflowBuildRepositoryMock = &deployer.MockWorkflowBuildsRepository{}
	s.repositoryClientFactoryMock = &azp.MockRepositoryClientFactory{}
	s.repositoryClientMock = &azp.MockRepositoryClient{}
	s.ghTwirpClientMock = &ghtwirp.MockClient{}
	s.log = log
	s.reporter = NewAdminEventsReporter(obs, s.workflowBuildRepositoryMock, s.repositoryClientFactoryMock, s.azpResourcesRepo, s.ghTwirpClientMock)
}

// extracted for readability
func (s *AdminEventsReporterSuite) MatchOrganization(gid types.GlobalID) bool {
	t, _, err := gid.Decode()
	if err != nil {
		s.NoError(err)
	}
	s.Equal(t, types.GlobalIDOrganizationType)
	return true
}

// extracted for readability
func (s *AdminEventsReporterSuite) MatchRepo(gid types.GlobalID) bool {
	t, _, err := gid.Decode()
	if err != nil {
		s.NoError(err)
	}
	s.Equal(t, types.GlobalIDRepositoryType)
	return true
}

func (s *AdminEventsReporterSuite) Test_SuccessfulReportRepoSpammyUser() {
	ctx := context.Background()

	s.repositoryClientMock.On("ReportAdminEvent", mock.Anything, OwnerMarkedAsSpammy, mock.Anything).Return(nil)
	s.repositoryClientFactoryMock.On("ClientFromRepoGID", mock.Anything, testRepositoryGlobalID).Return(s.repositoryClientMock, nil)
	data := map[string]string{
		"owner":  testOrg,
		"repo":   testRepo,
		"reason": testSpammyReason,
	}
	err := s.reporter.ReportRepoAdminEvent(ctx, testRepositoryGlobalID, OwnerMarkedAsSpammy, data)

	s.NoError(err)
	s.repositoryClientMock.AssertExpectations(s.T())
}

func (s *AdminEventsReporterSuite) Test_ReportRepoAdminEventFail_NoBackResource() {
	ctx := context.Background()

	s.repositoryClientFactoryMock.On("ClientFromRepoGID", mock.Anything, testRepositoryGlobalID).Return(nil, deployer.NewGetAzpResourcesError(testRepositoryGlobalID))
	data := map[string]string{
		"owner":  testOrg,
		"repo":   testRepo,
		"reason": testSpammyReason,
	}
	err := s.reporter.ReportRepoAdminEvent(ctx, testRepositoryGlobalID, OwnerMarkedAsSpammy, data)

	s.NoError(err)
	s.repositoryClientMock.AssertExpectations(s.T())
}

func (s *AdminEventsReporterSuite) Test_ReportRepoUnknownAdminEvent() {
	ctx := context.Background()

	data := map[string]string{
		"owner":  testOrg,
		"repo":   testRepo,
		"reason": testSpammyReason,
	}
	s.repositoryClientFactoryMock.On("ClientFromRepoGID", mock.Anything, testRepositoryGlobalID).Return(s.repositoryClientMock, nil)

	err := s.reporter.ReportRepoAdminEvent(ctx, testRepositoryGlobalID, "UnKnown", data)

	s.Error(err)
	s.repositoryClientMock.AssertExpectations(s.T())
}

func (s *AdminEventsReporterSuite) Test_RepositoryDeleted_DeleteAzpResources() {
	s.repositoryClientMock.On("ReportAdminEvent", mock.Anything, RepositoryDeleted, mock.Anything).Return(nil)
	s.repositoryClientFactoryMock.On("ClientFromRepoGID", mock.Anything, testRepositoryGlobalID).Return(s.repositoryClientMock, nil)
	s.azpResourcesRepo.On("ArchiveEntity", mock.Anything, mock.Anything).Return(int64(1), nil)

	ctx := context.Background()

	data := map[string]string{
		"owner":  testOrg,
		"repo":   testRepo,
		"reason": RepositoryDeleted,
	}

	err := s.reporter.ReportRepoAdminEvent(ctx, testRepositoryGlobalID, RepositoryDeleted, data)
	s.NoError(err)

	s.repositoryClientMock.AssertExpectations(s.T())
}

func (s *AdminEventsReporterSuite) Test_ReportRepoAdminEventFail_HandleMultipleAdminEventTypes() {
	ctx := context.Background()

	s.repositoryClientFactoryMock.On("ClientFromRepoGID", mock.Anything, testRepositoryGlobalID).Return(s.repositoryClientMock, nil)

	s.azpResourcesRepo.On("ArchiveEntity", mock.Anything, mock.Anything).Return(int64(1), nil)

	repoAdminEvents := []string{OwnerMarkedAsSpammy, OwnerInvocationBlocked}

	for _, adminEvent := range repoAdminEvents {
		data := map[string]string{
			"owner":  testOrg,
			"repo":   testRepo,
			"reason": "test-reason",
		}
		s.repositoryClientMock.On("ReportAdminEvent", mock.Anything, adminEvent, data).Return(nil)
		err := s.reporter.ReportRepoAdminEvent(ctx, testRepositoryGlobalID, adminEvent, data)
		s.NoError(err)
	}

	repoAdminEvents = []string{RepositoryDeleted, RepositoryArchived, RepositoryTransferred}

	for _, adminEvent := range repoAdminEvents {
		data := map[string]string{
			"repo_global_id": testRepositoryGlobalID.String(),
		}
		s.repositoryClientMock.On("ReportAdminEvent", mock.Anything, adminEvent, data).Return(nil)
		err := s.reporter.ReportRepoAdminEvent(ctx, testRepositoryGlobalID, adminEvent, data)
		s.NoError(err)
	}

	s.repositoryClientMock.AssertExpectations(s.T())
}

func (s *AdminEventsReporterSuite) Test_ReportRepoSpammyUserFail_AzpRequest() {
	ctx := context.Background()

	s.repositoryClientMock.On("ReportAdminEvent", mock.Anything, OwnerMarkedAsSpammy, mock.Anything).Return(errors.New("azp error"))
	s.repositoryClientFactoryMock.On("ClientFromRepoGID", mock.Anything, testRepositoryGlobalID).Return(s.repositoryClientMock, nil)

	data := map[string]string{
		"owner":  testOrg,
		"repo":   testRepo,
		"reason": testSpammyReason,
	}
	err := s.reporter.ReportRepoAdminEvent(ctx, testRepositoryGlobalID, OwnerMarkedAsSpammy, data)

	s.Error(err)
	s.repositoryClientMock.AssertExpectations(s.T())
}

func (s *AdminEventsReporterSuite) Test_SuccessfulReportBillingOwnerDeleted() {
	ctx := context.Background()

	s.repositoryClientMock.On("ReportAdminEvent", mock.Anything, BillingOwnerDeleted, mock.Anything).Return(nil)
	s.repositoryClientMock.On("ReportRunnerAdminEvent", mock.Anything, BillingOwnerDeleted, mock.Anything).Return(nil)
	s.repositoryClientFactoryMock.On("ClientFromRepoGID", mock.Anything, testBillingOwnerGlobalID).Return(s.repositoryClientMock, nil)

	err := s.reporter.ReportBillingOwnerAdminEvent(ctx, testBillingOwnerGlobalID, testOrg, BillingOwnerDeleted, "test data")

	s.NoError(err)
	s.repositoryClientMock.AssertExpectations(s.T())
}

// tests that adding a feature flag for the new code path does the same thing
func (s *AdminEventsReporterSuite) Test_SuccessfulReportBillingOwnerDeleted_ToBothServices() {
	ctx := context.Background()

	s.repositoryClientMock.On("ReportAdminEvent", mock.Anything, BillingOwnerDeleted, mock.Anything).Return(nil)
	s.repositoryClientMock.On("ReportRunnerAdminEvent", mock.Anything, BillingOwnerDeleted, mock.Anything).Return(nil)
	s.repositoryClientFactoryMock.On("ClientFromRepoGID", mock.Anything, testBillingOwnerGlobalID).Return(s.repositoryClientMock, nil)

	err := s.reporter.ReportBillingOwnerAdminEvent(ctx, testBillingOwnerGlobalID, testOrg, BillingOwnerDeleted, "test data")

	s.NoError(err)
	s.repositoryClientMock.AssertExpectations(s.T())
}

func (s *AdminEventsReporterSuite) Test_ReportBillingOwnerAbuseEvents_OnlySendToRunner() {
	cases := []struct {
		name       string
		adminEvent string
	}{
		{
			"OwnerInvocationBlocked",
			OwnerInvocationBlocked,
		},
		{
			"OwnerInvocationUnblocked",
			OwnerInvocationUnblocked,
		},
		{
			"OwnerMarkedAsSpammy",
			OwnerMarkedAsSpammy,
		},
		{
			"OwnerUnmarkedAsSpammy",
			OwnerUnmarkedAsSpammy,
		},
	}

	for _, tc := range cases {
		s.repositoryClientMock.On("ReportRunnerAdminEvent", mock.Anything, tc.adminEvent, mock.Anything).Return(nil)
		s.repositoryClientFactoryMock.On("ClientFromRepoGID", mock.Anything, testBillingOwnerGlobalID).Return(s.repositoryClientMock, nil)

		s.Run(tc.name, func() {
			ctx := context.Background()

			err := s.reporter.ReportBillingOwnerAdminEvent(ctx, testBillingOwnerGlobalID, testOrg, tc.adminEvent, "test data")

			s.NoError(err)
			s.repositoryClientMock.AssertNotCalled(s.T(), "ReportAdminEvent", mock.Anything, mock.Anything, mock.Anything)
			s.repositoryClientMock.AssertExpectations(s.T())
		})
	}
}

func (s *AdminEventsReporterSuite) Test_ReportBillingOwnerAdminEventFail_NoBackResource() {
	ctx := context.Background()

	s.repositoryClientFactoryMock.On("ClientFromRepoGID", mock.Anything, testBillingOwnerGlobalID).Return(nil, deployer.NewGetAzpResourcesError(testRepositoryGlobalID))

	err := s.reporter.ReportBillingOwnerAdminEvent(ctx, testBillingOwnerGlobalID, testOrg, BillingOwnerDeleted, "test data")

	s.NoError(err)
	s.repositoryClientMock.AssertExpectations(s.T())
}

func (s *AdminEventsReporterSuite) Test_ReportBillingOwnerDeleted_SendsToRunner_WhenActionsFails() {
	ctx := context.Background()

	s.repositoryClientMock.On("ReportAdminEvent", mock.Anything, BillingOwnerDeleted, mock.Anything).Return(errors.New("actions error"))
	s.repositoryClientMock.On("ReportRunnerAdminEvent", mock.Anything, BillingOwnerDeleted, mock.Anything).Return(nil)
	s.repositoryClientFactoryMock.On("ClientFromRepoGID", mock.Anything, testBillingOwnerGlobalID).Return(s.repositoryClientMock, nil)

	err := s.reporter.ReportBillingOwnerAdminEvent(ctx, testBillingOwnerGlobalID, testOrg, BillingOwnerDeleted, "test data")

	s.Error(err)
	s.Contains(err.Error(), "could not report admin event to azp actions service")
	s.NotContains(err.Error(), "could not report admin event to azp runner service")
	s.repositoryClientMock.AssertExpectations(s.T())
}

func (s *AdminEventsReporterSuite) Test_ReportBillingOwnerDeleted_SendsToActions_WhenRunnerFails() {
	ctx := context.Background()

	s.repositoryClientMock.On("ReportAdminEvent", mock.Anything, BillingOwnerDeleted, mock.Anything).Return(nil)
	s.repositoryClientMock.On("ReportRunnerAdminEvent", mock.Anything, BillingOwnerDeleted, mock.Anything).Return(errors.New("actions error"))
	s.repositoryClientFactoryMock.On("ClientFromRepoGID", mock.Anything, testBillingOwnerGlobalID).Return(s.repositoryClientMock, nil)

	err := s.reporter.ReportBillingOwnerAdminEvent(ctx, testBillingOwnerGlobalID, testOrg, BillingOwnerDeleted, "test data")

	s.Error(err)
	s.NotContains(err.Error(), "could not report admin event to azp actions service")
	s.Contains(err.Error(), "could not report admin event to azp runner service")
	s.repositoryClientMock.AssertExpectations(s.T())
}

func (s *AdminEventsReporterSuite) Test_ReportBillingOwnerUnknownAdminEvent() {
	ctx := context.Background()

	s.repositoryClientFactoryMock.On("ClientFromRepoGID", mock.Anything, testBillingOwnerGlobalID).Return(s.repositoryClientMock, nil)

	err := s.reporter.ReportBillingOwnerAdminEvent(ctx, testBillingOwnerGlobalID, testOrg, "UNKNOWN", "test data")

	s.Error(err)
	s.repositoryClientMock.AssertExpectations(s.T())
}

func (s *AdminEventsReporterSuite) Test_ReportBillingOwnerSpammyUserFail_AzpRequest() {
	ctx := context.Background()

	s.repositoryClientMock.On("ReportAdminEvent", mock.Anything, BillingOwnerDeleted, mock.Anything).Return(errors.New("azp error"))
	s.repositoryClientMock.On("ReportRunnerAdminEvent", mock.Anything, BillingOwnerDeleted, mock.Anything).Return(nil)
	s.repositoryClientFactoryMock.On("ClientFromRepoGID", mock.Anything, testBillingOwnerGlobalID).Return(s.repositoryClientMock, nil)

	err := s.reporter.ReportBillingOwnerAdminEvent(ctx, testBillingOwnerGlobalID, testOrg, BillingOwnerDeleted, "test data")

	s.Error(err)
	s.repositoryClientMock.AssertExpectations(s.T())
}

func (s *AdminEventsReporterSuite) Test_SuccessfulReportBillingOwnerRestored() {
	ctx := context.Background()

	s.repositoryClientMock.On("ReportAdminEvent", mock.Anything, BillingOwnerRestored, mock.Anything).Return(nil)
	s.repositoryClientFactoryMock.On("ClientFromRepoGID", mock.Anything, testBillingOwnerGlobalID).Return(s.repositoryClientMock, nil)

	err := s.reporter.ReportBillingOwnerAdminEvent(ctx, testBillingOwnerGlobalID, testOrg, BillingOwnerRestored, "test data")

	s.NoError(err)
	s.repositoryClientMock.AssertExpectations(s.T())
}
