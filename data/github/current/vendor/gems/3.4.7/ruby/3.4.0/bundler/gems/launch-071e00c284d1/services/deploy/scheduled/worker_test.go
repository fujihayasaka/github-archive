package scheduled

import (
	context "context"
	"encoding/json"
	"fmt"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	mock "github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"

	"github.com/github/launch/cli"
	"github.com/github/launch/clients/aqueduct"
	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/github"
	"github.com/github/launch/db/stores/schedules"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/pkg/cache/cachemem"
	"github.com/github/launch/pkg/launchcache"
	"github.com/github/launch/pkg/processors/build"
	"github.com/github/launch/services/deploy/scheduled/config"
	"github.com/github/launch/types"
)

const (
	MiB = 1 << 20
)

func TestWorkerTick(t *testing.T) {
	type testCase struct {
		desc                      string
		expectedError             error
		areSchedulesDisabled      bool
		areSchedulesDisabledInLab bool
		expectedFeatureFlagCalls  int
		isEnterprise              bool
		isLab                     bool
		queueDepth                int
	}

	tests := []testCase{
		{
			desc:                      "returns no error when schedules are disabled and it's the lab environment",
			areSchedulesDisabled:      false,
			areSchedulesDisabledInLab: true,
			expectedError:             nil,
			expectedFeatureFlagCalls:  2,
			isEnterprise:              false,
			isLab:                     true,
		},
		{
			desc:                      "returns no error when schedules are disabled in production",
			areSchedulesDisabled:      true,
			areSchedulesDisabledInLab: false,
			expectedError:             nil,
			expectedFeatureFlagCalls:  1,
			isEnterprise:              false,
			isLab:                     false,
		},
		{
			desc:                      "does not call feature flag API when in enterprise mode",
			areSchedulesDisabled:      false,
			areSchedulesDisabledInLab: false,
			expectedError:             nil,
			expectedFeatureFlagCalls:  0,
			isEnterprise:              true,
			isLab:                     false,
		},
		{
			desc:                      "does not call feature flag API for lab when in production",
			areSchedulesDisabled:      false,
			areSchedulesDisabledInLab: true,
			expectedError:             nil,
			expectedFeatureFlagCalls:  1,
			isEnterprise:              false,
			isLab:                     false,
		},
		{
			desc:                      "does not call FindAndLock if depth > maximumQueueDepth",
			areSchedulesDisabled:      false,
			areSchedulesDisabledInLab: false,
			expectedFeatureFlagCalls:  1,
			isEnterprise:              false,
			isLab:                     false,
			queueDepth:                501,
		},
		{
			desc:                      "does call FindAndLock when in enterprise mode regardless of queueDepth",
			areSchedulesDisabled:      false,
			areSchedulesDisabledInLab: false,
			expectedError:             nil,
			expectedFeatureFlagCalls:  0,
			isEnterprise:              true,
			isLab:                     false,
			queueDepth:                300,
		},
		{
			desc:                      "does call FindAndLock if depth < queueDepthThreshold",
			areSchedulesDisabled:      false,
			areSchedulesDisabledInLab: false,
			expectedError:             nil,
			expectedFeatureFlagCalls:  1,
			isEnterprise:              false,
			isLab:                     false,
			queueDepth:                99,
		},
		{
			desc:                      "does call FindAndLock if depth < maximumQueueDepth and depth > queueDepthThreshold",
			areSchedulesDisabled:      false,
			areSchedulesDisabledInLab: true,
			expectedError:             nil,
			expectedFeatureFlagCalls:  1,
			isEnterprise:              false,
			isLab:                     false,
			queueDepth:                499,
		},
	}

	for _, tt := range tests {
		t.Run(tt.desc, func(t *testing.T) {
			store := &schedules.MockStore{}
			tasksPerTick := int(10)

			// mock the FindAndLock call only if the code will get there
			if (tt.isLab && !tt.areSchedulesDisabledInLab) || (!tt.isLab && !tt.areSchedulesDisabled) {
				if tt.queueDepth < 100 {
					store.On("FindAndLock", mock.Anything, mock.Anything, tasksPerTick).Return(nil, nil)
				} else if tt.queueDepth < 500 && tt.queueDepth > 100 {
					store.On("FindAndLock", mock.Anything, mock.Anything, tasksPerTick/2).Return(nil, nil)
				}
			}

			appMetadata := cli.GetApplicationMetadata("testing")

			aqueductClient := &aqueduct.MockClient{}

			mockTwirpClient := &ghtwirp.MockClient{}
			mockTwirpClient.On("IsFeatureEnabledGlobally", mock.Anything, github.DisableScheduledWorkflowsFeatureFlag).Return(tt.areSchedulesDisabled)
			mockTwirpClient.On("IsFeatureEnabledGlobally", mock.Anything, github.DisableScheduledWorkflowsInLabFeatureFlag).Return(tt.areSchedulesDisabledInLab)

			var ghTwirpClient ghtwirp.Client = mockTwirpClient
			if tt.isEnterprise {
				ghTwirpClient = ghtwirp.NewEnterpriseClient(mockTwirpClient)
			}

			cache := launchcache.NewNamespacedCache(cachemem.NewExpiringCache(1*MiB), observability.NewNullObservability()).LaunchDependency()

			worker := newWorker(
				"test",
				store,
				logger.NullLogger(),
				config.ScheduledConfig{
					TasksPerTick: tasksPerTick,
				},
				statter.NullStatter(),
				appMetadata,
				ghTwirpClient,
				aqueductClient,
				"queue",
				"app",
				tt.isEnterprise,
				tt.isLab,
				false,
				cache,
			)

			cache.AqueductQueueDepthCacheFor(worker.aqueductQueue).Set(context.Background(), int64(tt.queueDepth), 300*time.Second)

			err := worker.tick(context.Background())
			assert.Equal(t, tt.expectedError, err)

			mockTwirpClient.AssertNumberOfCalls(t, "IsFeatureEnabledGlobally", tt.expectedFeatureFlagCalls)

			store.AssertExpectations(t)
		})
	}
}

func TestUpdateTierIfExpired(t *testing.T) {
	tests := []struct {
		desc                string
		shouldCalculateTier bool
		isEnterprise        bool
		isMultiTenant       bool
	}{
		{
			desc:                "calculates tier for non-enterprise",
			shouldCalculateTier: true,
			isEnterprise:        false,
		},
		{
			desc:                "tier 1 without call for enterprise",
			shouldCalculateTier: false,
			isEnterprise:        true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.desc, func(t *testing.T) {
			store := &schedules.MockStore{}
			tasksPerTick := int(10)
			appMetadata := cli.GetApplicationMetadata("testing")
			aqueductClient := &aqueduct.MockClient{}
			cache := launchcache.NewNamespacedCache(cachemem.NewExpiringCache(1*MiB), observability.NewNullObservability()).LaunchDependency()

			ghTwirpClient := &ghtwirp.MockClient{}
			ghTwirpClient.On("GetTrustTier", mock.Anything, mock.Anything).Return(types.RepositoryTier3, nil)

			worker := newWorker(
				"test",
				store,
				logger.NullLogger(),
				config.ScheduledConfig{
					TasksPerTick: tasksPerTick,
				},
				statter.NullStatter(),
				appMetadata,
				ghTwirpClient,
				aqueductClient,
				"queue",
				"app",
				tt.isEnterprise,
				false,
				tt.isMultiTenant,
				cache,
			)

			schedule := schedules.ScheduleRun{}

			worker.updateTierIfExpired(context.Background(), &schedule)

			if tt.shouldCalculateTier {
				ghTwirpClient.AssertNumberOfCalls(t, "GetTrustTier", 1)

				assert.Equal(t, types.RepositoryTier3, schedule.Tier)
			} else {
				ghTwirpClient.AssertNumberOfCalls(t, "GetTrustTier", 0)

				assert.Equal(t, types.RepositoryTier1, schedule.Tier)
			}
		})
	}
}

func Test_Queue_Scheduled_Workflow_MultiTenant_Environment(t *testing.T) {
	githubTenantSubdomain := "github"

	var githubTenantID int64 = 1
	var githubTenantIDFromDB int64 = 2

	nextRun := time.Now().Add(1 * time.Minute)
	tierUpdatedAt := time.Now().Add(-1 * time.Minute)

	// at present twirpclient.GetRepositoryEventDetails does not return a typed struct so we have to use a raw string here
	// the tenenant subdomain is expected to be present in the enterprise.slug field of the response. Value of the slug is injected
	// at test execution time
	scheduledEventDetailsStubTmpl := `{ "repo": {}, "organization": {}, "enterprise": {%v, "slug": %v} }`

	validID := fmt.Sprintf(`"id": %d`, githubTenantID)
	invalidID := fmt.Sprintf(`"id": "%d"`, 27)
	missingIDField := ""
	validSlug := fmt.Sprintf(`"%s"`, githubTenantSubdomain)
	invalidSlug := 27

	// setup a db record with a github tenant id to make sure that the
	// tenant id comes from the API instead of the db
	stubSchedule := schedules.ScheduleRun{
		ID:                 1,
		RepositoryNodeID:   "R_kgDOAAFjIg",
		Schedule:           "*/5 * * * *",
		ActorNodeID:        "actor1",
		ActorLogin:         "actor1",
		CommitSHA:          "sha1",
		WorkflowIdentifier: "workflow1",
		WorkflowFilePath:   "workflow1.yml",
		NextRunAt:          &nextRun,
		Tier:               types.RepositoryTier1,
		TierUpdatedAt:      &tierUpdatedAt,
		GitHubTenantID:     &githubTenantIDFromDB,
	}

	tests := []struct {
		desc string
		// tenant subdomain (slug) and id comes back from an API call to the GitHub API. The corresponding event created from the response
		// is flowevents.ScheduleEventPayload. Data in this struct is map[string]interface{} so test cases do the same so
		// we can validate behavior on malformed data
		enterpriseSlugResponse       interface{}
		enterpriseIDResponse         interface{}
		shouldPublishAqueductMessage bool
	}{
		{
			desc:                         "message published when enterprise tenant id and subdomain in event",
			enterpriseIDResponse:         validID,
			enterpriseSlugResponse:       validSlug,
			shouldPublishAqueductMessage: true,
		},
		{
			desc:                         "no messaage published when tenant id not in event",
			enterpriseIDResponse:         missingIDField,
			enterpriseSlugResponse:       validSlug,
			shouldPublishAqueductMessage: false,
		},
		{
			desc:                         "no message published when tenant id in event is malformed",
			enterpriseIDResponse:         invalidID,
			enterpriseSlugResponse:       validSlug,
			shouldPublishAqueductMessage: false,
		},
		{
			desc:                         "no message published when tenant subdomain is missing",
			enterpriseIDResponse:         validID,
			shouldPublishAqueductMessage: false,
		},
		{
			desc:                         "no message publishing when tenant subdomain is malformed",
			enterpriseIDResponse:         validID,
			enterpriseSlugResponse:       invalidSlug,
			shouldPublishAqueductMessage: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.desc, func(t *testing.T) {
			r := require.New(t)

			store := &schedules.MockStore{}
			store.On("ScheduleNextRun", mock.Anything, mock.Anything).Return(nil)

			appMetadata := cli.GetApplicationMetadata("testing")

			mockAqueductClient := &aqueduct.MockClient{}
			call := mockAqueductClient.On("Send", mock.Anything, mock.Anything).Return("jobID", nil)

			call.RunFn = func(args mock.Arguments) {
				aqueductJob := args.Get(1).(aqueduct.Job)

				var invocationJob build.Job
				err := json.Unmarshal(aqueductJob.Payload, &invocationJob)
				r.NoError(err, "expected aqueduct job payload to be an Invocation struct")

				githubTenant := invocationJob.Invocation.Target.GitHubTenant
				r.Equal(githubTenantID, githubTenant.ID)
				r.Equal(githubTenantSubdomain, githubTenant.Slug)
			}

			mockTwirpClient := &ghtwirp.MockClient{}
			mockTwirpClient.On("IsRepositoryActionsDisabled", mock.Anything, mock.Anything).Return(false, nil)
			mockTwirpClient.On("GetTrustTier", mock.Anything, mock.Anything).Return(types.RepositoryTier1, nil)
			mockTwirpClient.On("GetRepositoryOwnerID", mock.Anything, mock.Anything, true).Return(int64(42), nil)
			store.On("UpdateOwnerID", mock.Anything, mock.Anything, mock.Anything).Return(nil)

			scheduledEventDetailsStub := fmt.Sprintf(scheduledEventDetailsStubTmpl, tt.enterpriseIDResponse, tt.enterpriseSlugResponse)
			mockTwirpClient.On("GetRepositoryEventDetails", mock.Anything, mock.Anything).Return(scheduledEventDetailsStub, nil)

			cache := launchcache.NewNamespacedCache(cachemem.NewExpiringCache(1*MiB), observability.NewNullObservability()).LaunchDependency()

			worker := newWorker(
				"test",
				store,
				logger.NullLogger(),
				config.ScheduledConfig{
					TasksPerTick: 10,
				},
				statter.NullStatter(),
				appMetadata,
				mockTwirpClient,
				mockAqueductClient,
				"queue",
				"app",
				false,
				false,
				true,
				cache,
			)

			worker.run(context.Background(), stubSchedule)

			if tt.shouldPublishAqueductMessage {
				mockAqueductClient.AssertNumberOfCalls(t, "Send", 1)
			} else {
				mockAqueductClient.AssertNumberOfCalls(t, "Send", 0)
			}
		})
	}
}
