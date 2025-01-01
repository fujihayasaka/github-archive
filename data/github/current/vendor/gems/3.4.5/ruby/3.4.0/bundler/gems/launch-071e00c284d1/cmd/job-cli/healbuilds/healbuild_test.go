package healbuilds

import (
	"context"
	"testing"
	"time"

	"github.com/github/launch/db/stores/deployer"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"github.com/stretchr/testify/suite"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/pkg/azp"
	"github.com/github/launch/pkg/buildhealer"
	"github.com/github/launch/pkg/cache/cachemem"
	"github.com/github/launch/pkg/launchcache"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/appcontext"
	"github.com/github/launch/utils/testutils"
	"github.com/github/launch/workflowbuild/build"
)

const (
	repoID = types.GlobalID("my-rad-repo")
	MiB    = 1 << 20
)

type healBuildSuite struct {
	suite.Suite

	ghTwirpClient         *ghtwirp.MockClient
	mockRepoClientFactory *azp.MockRepositoryClientFactory
	mockRepoClient        *azp.MockRepositoryClient
	mockHealer            *mockHealer
	cache                 launchcache.HealingJobCache
}

func TestHealBuild(t *testing.T) {
	suite.Run(t, new(healBuildSuite))
}

func (s *healBuildSuite) SetupTest() {
	s.ghTwirpClient = &ghtwirp.MockClient{}
	s.mockRepoClientFactory = &azp.MockRepositoryClientFactory{}
	s.mockRepoClient = &azp.MockRepositoryClient{}

	s.mockHealer = &mockHealer{}

	s.cache = launchcache.NewNamespacedCache(cachemem.NewExpiringCache(1*MiB), observability.NewNullObservability()).HealingJob()
}

func (s *healBuildSuite) Test_HealWorkflows() {
	utcNow := time.Now().UTC()
	fiveMinutesAgo := time.Now().Add(-5 * time.Minute)
	fiveHoursAgo := time.Now().Add(-5 * time.Hour)
	fiftyOneHoursAgo := utcNow.Add(-51 * time.Hour)
	thirtyFourDaysAgo := utcNow.Add(-34 * 24 * time.Hour)
	thirtySixDaysAgo := utcNow.Add(-36 * 24 * time.Hour)
	emptyExternalId := ""

	cases := []struct {
		name                string
		buildCreatedAt      *time.Time
		state               build.WorkflowState
		runInfo             *azp.RunInfoResponse
		externalID          *string
		conclusion          string
		healingExpected     bool
		runInfoCallExpected bool
		cancelRunExpected   bool
		logMsgs             []string
		fetchClientFails    bool
	}{
		{
			name:                "inProgress run not healed",
			state:               build.WorkflowStateStarted,
			runInfo:             &azp.RunInfoResponse{Status: "inProgress", StartedAt: &utcNow},
			healingExpected:     false,
			cancelRunExpected:   false,
			runInfoCallExpected: true,
			logMsgs:             []string{"skipped workflow healing because it is currently in progress"},
		},
		{
			name:                "recently queued run not healed or cancelled",
			buildCreatedAt:      &utcNow,
			state:               build.WorkflowStateStarted,
			runInfo:             &azp.RunInfoResponse{Status: "inProgress", StartedAt: nil},
			healingExpected:     false,
			cancelRunExpected:   false,
			runInfoCallExpected: true,
			logMsgs:             []string{"skipped workflow healing because it is currently queued"},
		},
		{
			name:                "Run queued for a long time cancelled and not healed",
			buildCreatedAt:      &fiftyOneHoursAgo,
			state:               build.WorkflowStateStarted,
			runInfo:             &azp.RunInfoResponse{Status: "inProgress", StartedAt: nil},
			healingExpected:     false,
			cancelRunExpected:   true,
			runInfoCallExpected: true,
			logMsgs:             []string{"skipped workflow healing because it is currently queued"},
		},
		{
			name:                "Run queued for a long time without an external ID not cancelled",
			buildCreatedAt:      &fiftyOneHoursAgo,
			state:               build.WorkflowStateStarted,
			runInfo:             &azp.RunInfoResponse{Status: "inProgress", StartedAt: nil},
			externalID:          &emptyExternalId,
			healingExpected:     false,
			cancelRunExpected:   false,
			runInfoCallExpected: true,
			logMsgs:             []string{"cannot cancel run with empty external ID", "skipped workflow healing because it is currently queued"},
		},
		{
			name:                "Run in-progress for a long time cancelled and not healed",
			buildCreatedAt:      &thirtySixDaysAgo,
			state:               build.WorkflowStateStarted,
			runInfo:             &azp.RunInfoResponse{Status: "inProgress", StartedAt: &thirtyFourDaysAgo},
			healingExpected:     false,
			cancelRunExpected:   true,
			runInfoCallExpected: true,
			logMsgs:             []string{"skipped workflow healing because it is currently in progress"},
		},
		{
			name:                "recently completed run not healed",
			runInfo:             &azp.RunInfoResponse{Status: "completed", StartedAt: &fiftyOneHoursAgo, CompletedAt: &fiveMinutesAgo, Conclusion: "failed"},
			healingExpected:     false,
			cancelRunExpected:   false,
			runInfoCallExpected: true,
			logMsgs:             []string{"skipped workflow healing during postback grace period", "gh.launch.since_completion_minutes=5"},
		},
		{
			name:                "run completed several hours ago healed",
			runInfo:             &azp.RunInfoResponse{Status: "completed", StartedAt: &fiftyOneHoursAgo, CompletedAt: &fiveHoursAgo, Conclusion: "failed"},
			conclusion:          "failed",
			healingExpected:     true,
			cancelRunExpected:   false,
			runInfoCallExpected: true,
			logMsgs:             []string{"gh.launch.since_completion_minutes=300"},
		},
		{
			// Completed runs sometimes don't have started_at set. See https://github.com/github/c2c-actions-runtime/issues/1364
			name:                "completed run without started_at healed",
			runInfo:             &azp.RunInfoResponse{Status: "completed", CompletedAt: &fiveHoursAgo, Conclusion: "failed"},
			conclusion:          "failed",
			healingExpected:     true,
			cancelRunExpected:   false,
			runInfoCallExpected: true,
		},
		{
			name:                "completed run without completed_at not healed",
			runInfo:             &azp.RunInfoResponse{Status: "completed", Conclusion: "failed"},
			conclusion:          "failed",
			healingExpected:     false,
			cancelRunExpected:   false,
			runInfoCallExpected: true,
			logMsgs:             []string{"completed workflow run missing completed_at time"},
		},
		{
			name:                "unrecognized status",
			state:               build.WorkflowStateStarted,
			runInfo:             &azp.RunInfoResponse{Status: "notAStatus"},
			healingExpected:     false,
			cancelRunExpected:   false,
			runInfoCallExpected: true,
			logMsgs:             []string{"workflow run status not recognized", "gh.launch.workflow_run.status=notAStatus"},
		},
		{
			name:                "run not queued to Actions Service healed",
			state:               build.WorkflowStateNone,
			runInfo:             nil,
			conclusion:          "canceled",
			healingExpected:     true,
			cancelRunExpected:   false,
			runInfoCallExpected: true,
			logMsgs:             []string{"Run not queued."},
		},
		{
			name:                "run not found by Actions Service healed",
			state:               build.WorkflowStateStarted,
			runInfo:             nil,
			conclusion:          "canceled",
			healingExpected:     true,
			cancelRunExpected:   false,
			runInfoCallExpected: true,
			logMsgs:             []string{"Queued run not found."},
		},
		{
			name:                "skip on cache hit",
			state:               build.WorkflowStateStarted,
			runInfo:             nil,
			healingExpected:     false,
			cancelRunExpected:   false,
			runInfoCallExpected: false,
			logMsgs:             []string{"skipped workflow healing because it is cached as skippable"},
		},
		{
			name:                "azp_resources not found is considered repo_deleted and healed",
			state:               build.WorkflowStateStarted,
			runInfo:             nil,
			conclusion:          "canceled",
			healingExpected:     true,
			cancelRunExpected:   false,
			runInfoCallExpected: false,
			logMsgs:             []string{"healed workflow in launch"},
			fetchClientFails:    true,
		},
	}

	for i, tc := range cases {
		s.Run(tc.name, func() {
			log := testutils.NewRecordingLogger()
			obs := observability.New(log.Logger, statter.NullStatter())

			s.mockRepoClientFactory = &azp.MockRepositoryClientFactory{} // need to reset for each test case

			uuid := types.NewRandomWorkflowExecutionID()
			runner := Runner{
				obs:                  obs,
				serviceClientFactory: s.mockRepoClientFactory,
				cacheClient:          s.cache,
				ghTwirpClient:        s.ghTwirpClient,
			}

			externalID := "1234"
			if tc.externalID != nil {
				externalID = *tc.externalID
			}

			w := buildhealer.WorkflowInfo{
				RepositoryID:    repoID,
				CreatedAt:       tc.buildCreatedAt,
				CheckSuiteID:    types.GlobalID("checksuite-1"),
				State:           tc.state,
				UUID:            uuid,
				ExternalBuildID: externalID,
				ID:              int64(2341234 + i),
				ExecutionID:     int64(2341235 + i),
			}

			if tc.fetchClientFails {
				s.mockRepoClientFactory.On("ClientFromRepoGID", mock.Anything, repoID).
					Return(nil, deployer.NewGetAzpResourcesError(repoID))
			} else {
				s.mockRepoClientFactory.On("ClientFromRepoGID", mock.Anything, repoID).
					Return(s.mockRepoClient, nil)
			}

			if tc.runInfoCallExpected {
				s.mockRepoClient.On("RunInfo", mock.Anything, uuid).
					Return(tc.runInfo, nil)
			} else if !tc.fetchClientFails {
				s.cache.SkipWorkflowExecutionIDFor(w.ExecutionID).Set(context.Background(), "", 300*time.Second)
			}

			if tc.healingExpected {
				s.mockHealer.On("CompleteBuild", mock.Anything, w, "completed", tc.conclusion, buildhealer.ReasonScheduled).Return("", true, nil)
			}

			if tc.cancelRunExpected {
				s.mockRepoClient.On("Cancel", mock.Anything, w.ExternalBuildID, (*azp.CancelOptions)(nil)).Return(nil)
			}

			s.Equal(tc.healingExpected, runner.healWorkflow(getContextWithAppContext(), w, s.mockHealer, 3*time.Hour))

			s.mockHealer.AssertExpectations(s.T())
			s.mockRepoClient.AssertExpectations(s.T())

			if tc.healingExpected {
				s.Contains(log.String(), "healed workflow")
			}

			for _, logMsg := range tc.logMsgs {
				s.Contains(log.String(), logMsg)
			}
		})
	}
}

func getContextWithAppContext() context.Context {
	ctx, _ := appcontext.InitializeWithRequestID(context.Background(), appcontext.ApplicationMetadata{}, "job-cli")
	return ctx
}

func TestCalculateSkipTime(t *testing.T) {
	now := time.Now()
	tests := []struct {
		name string
		now  time.Time
		in   *time.Time
		want time.Duration
	}{
		{
			name: "if run is < default, return default",
			now:  now,
			in:   ptime(now.Add(-time.Hour)),
			want: defaultWaitTime,
		},
		{
			name: "if run hasn't started, return default",
			now:  now,
			in:   nil,
			want: defaultWaitTime,
		},
		{
			name: "if run is DefaultMaxHealableJobAge old, check it once per day",
			now:  now,
			in:   ptime(now.Add(-DefaultMaxHealableJobAge)),
			want: 24 * time.Hour,
		},
		// the other cases are scaled down according by a factor ~=0.003 (24h/744h)
		{
			name: "1h ago",
			now:  now,
			in:   ptime(now.Add(-time.Hour)),
			want: defaultWaitTime,
		},
		{
			name: "2h ago",
			now:  now,
			in:   ptime(now.Add(-2 * time.Hour)),
			want: defaultWaitTime,
		},
		{
			name: "3h ago",
			now:  now,
			in:   ptime(now.Add(-3 * time.Hour)),
			want: defaultWaitTime,
		},
		{
			name: "4h ago",
			now:  now,
			in:   ptime(now.Add(-4 * time.Hour)),
			want: defaultWaitTime,
		},
		{
			name: "5h ago",
			now:  now,
			in:   ptime(now.Add(-5 * time.Hour)),
			want: defaultWaitTime,
		},
		{
			name: "6h ago",
			now:  now,
			in:   ptime(now.Add(-6 * time.Hour)),
			want: defaultWaitTime,
		},
		{
			name: "7h ago",
			now:  now,
			in:   ptime(now.Add(-7 * time.Hour)),
			want: defaultWaitTime,
		},
		{
			name: "8h ago",
			now:  now,
			in:   ptime(now.Add(-8 * time.Hour)),
			want: defaultWaitTime,
		},
		{
			name: "9h ago",
			now:  now,
			in:   ptime(now.Add(-9 * time.Hour)),
			want: defaultWaitTime,
		},
		{
			name: "10h ago",
			now:  now,
			in:   ptime(now.Add(-10 * time.Hour)),
			want: defaultWaitTime,
		},
		{
			name: "11h ago",
			now:  now,
			in:   ptime(now.Add(-11 * time.Hour)),
			want: defaultWaitTime,
		},
		{
			name: "12h ago",
			now:  now,
			in:   ptime(now.Add(-12 * time.Hour)),
			want: defaultWaitTime,
		},
		{
			name: "13h ago",
			now:  now,
			in:   ptime(now.Add(-13 * time.Hour)),
			want: defaultWaitTime,
		},
		{
			name: "14h ago",
			now:  now,
			in:   ptime(now.Add(-14 * time.Hour)),
			want: defaultWaitTime,
		},
		{
			name: "15h ago",
			now:  now,
			in:   ptime(now.Add(-15 * time.Hour)),
			want: defaultWaitTime,
		},
		{
			name: "16h ago",
			now:  now,
			in:   ptime(now.Add(-16 * time.Hour)),
			want: defaultWaitTime,
		},
		{
			name: "17h ago",
			now:  now,
			in:   ptime(now.Add(-17 * time.Hour)),
			want: defaultWaitTime,
		},
		{
			name: "18h ago",
			now:  now,
			in:   ptime(now.Add(-18 * time.Hour)),
			want: defaultWaitTime,
		},
		{
			name: "19h ago",
			now:  now,
			in:   ptime(now.Add(-19 * time.Hour)),
			want: 30*time.Minute + 48*time.Second,
		},
		{
			name: "20h ago",
			now:  now,
			in:   ptime(now.Add(-20 * time.Hour)),
			want: 32*time.Minute + 25*time.Second,
		},
		{
			name: "21h ago",
			now:  now,
			in:   ptime(now.Add(-21 * time.Hour)),
			want: 34*time.Minute + 3*time.Second,
		},
		{
			name: "22h ago",
			now:  now,
			in:   ptime(now.Add(-22 * time.Hour)),
			want: 35*time.Minute + 40*time.Second,
		},
		{
			name: "23h ago",
			now:  now,
			in:   ptime(now.Add(-23 * time.Hour)),
			want: 37*time.Minute + 17*time.Second,
		},
		{
			name: "24h ago",
			now:  now,
			in:   ptime(now.Add(-24 * time.Hour)),
			want: 38*time.Minute + 55*time.Second,
		},
		{
			name: "72h ago",
			now:  now,
			in:   ptime(now.Add(-72 * time.Hour)),
			want: 1*time.Hour + 56*time.Minute + 45*time.Second,
		},
		{
			name: "360h ago", // 15 days
			now:  now,
			in:   ptime(now.Add(-360 * time.Hour)),
			want: 9*time.Hour + 43*time.Minute + 47*time.Second,
		},
		{
			name: "720h ago", // 30 days
			now:  now,
			in:   ptime(now.Add(-720 * time.Hour)),
			want: 19*time.Hour + 27*time.Minute + 34*time.Second,
		},
		{
			name: "1440h ago", // 60 days
			now:  now,
			in:   ptime(now.Add(-1440 * time.Hour)),
			want: 24 * time.Hour,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := calculateSkipTime(tt.now, tt.in)
			require.Equal(t, tt.want, got)
		})
	}
}

func ptime(t time.Time) *time.Time {
	return &t
}
