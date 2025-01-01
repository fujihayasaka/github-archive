package webhook

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/github/go-reqmeta"
	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"github.com/stretchr/testify/suite"

	"github.com/github/launch/clients/ghtwirp"
	ghclient "github.com/github/launch/clients/github"
	"github.com/github/launch/config/customerlabels"
	"github.com/github/launch/db/stores/deployer"
	hydroV0 "github.com/github/launch/hydro/schemas/github/actions/v0"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/slometrics"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/pkg/globalidmigration"
	mureqmeta "github.com/github/launch/pkg/mu/reqmeta"
	"github.com/github/launch/pkg/rate"
	"github.com/github/launch/pkg/schedulemanager"
	v1 "github.com/github/launch/proto/monolith/core/v1"
	"github.com/github/launch/services/deploy/adminevents"
	"github.com/github/launch/services/deploy/deliveryguid"
	"github.com/github/launch/services/deploy/workflowcanceler"
	"github.com/github/launch/services/deploy/workflowinvoker"
	"github.com/github/launch/services/pbtypes/launchtypes"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/ghtenant"
	"github.com/github/launch/utils/testutils"
)

const (
	testRobotAppID  = 9836
	testRobotNodeID = "BOT_kgDOAn9RKg"

	// Using actor IDs from monalisa with database ID 90914
	monalisaLogin   = "monalisa"
	monalisaActorId = types.GlobalID("U_kgDOAAFjIg")
)

type mocks struct {
	invoker            *workflowinvoker.MockInvoker
	wbRepo             *deployer.MockWorkflowBuildsRepository
	scheduleMngr       *schedulemanager.MockManager
	canceler           *workflowcanceler.MockCanceler
	reporter           *adminevents.MockReporter
	hydroEmitter       *slometrics.MockHydroEmitter
	ghTwirp            *ghtwirp.MockClient
	webhookRateLimiter *rate.MockRateLimiter
}

type webhookSuite struct {
	suite.Suite
	testLogger testutils.RecordingLogger
	m          mocks
}

func TestProcessor(t *testing.T) {
	suite.Run(t, new(webhookSuite))
}

func (s *webhookSuite) SetupTest() {
	s.testLogger = testutils.NewRecordingLogger()
	s.m.invoker = workflowinvoker.NewMockInvoker(s.T())
	s.m.wbRepo = deployer.NewMockWorkflowBuildsRepository(s.T())
	s.m.scheduleMngr = schedulemanager.NewMockManager(s.T())
	s.m.canceler = workflowcanceler.NewMockCanceler(s.T())
	s.m.reporter = adminevents.NewMockReporter(s.T())
	s.m.hydroEmitter = slometrics.NewMockHydroEmitter(s.T())
	s.m.ghTwirp = ghtwirp.NewMockClient(s.T())
	s.m.webhookRateLimiter = rate.NewMockRateLimiter(s.T())

	s.m.ghTwirp.On("GetNextGlobalID", mock.Anything, mock.Anything).
		Return(func(ctx context.Context, globalID string) types.GlobalID {
			s.Assert().True(types.IsNextGlobalID(globalID), "%s is not a global next ID", globalID)
			return types.GlobalID(globalID)
		}, nil).Maybe()

	s.m.ghTwirp.On("IsFeatureEnabledForRepository", mock.Anything, mock.Anything, mock.Anything).
		Return(func(ctx context.Context, featureFlagName string, repoID int64) bool {
			return false
		}, nil).Maybe()
}

func (s *webhookSuite) Test_SanitizePayload() {
	unallowedFields := []string{"meta", "actions_meta", "installation"}
	tests := []struct {
		name               string
		unsanitizedPayload []byte
		err                bool
		sanitizedPayload   []byte
	}{
		{
			name:               "empty payload",
			unsanitizedPayload: []byte{},
			err:                true,
			sanitizedPayload:   nil,
		},
		{
			name:               "pull request event",
			unsanitizedPayload: fixture(s.T(), "pull_request_event.json"),
			err:                false,
			sanitizedPayload:   fixture(s.T(), "sanitized/pull_request_event.json"),
		},
		{
			name:               "push event",
			unsanitizedPayload: fixture(s.T(), "push.json"),
			err:                false,
			sanitizedPayload:   fixture(s.T(), "sanitized/push.json"),
		},
		{
			name:               "robot check suite rerequested event",
			unsanitizedPayload: fixture(s.T(), "robot_check_suite_rerequested.json"),
			err:                false,
			sanitizedPayload:   fixture(s.T(), "sanitized/robot_check_suite_rerequested.json"),
		},
	}

	for _, tc := range tests {
		s.Run(tc.name, func() {
			output, err := sanitizePayload(tc.unsanitizedPayload)
			if tc.err {
				s.Error(err)
			} else {
				s.NoError(err)
				outputMap := map[string]any{}
				err := json.Unmarshal(output, &outputMap)
				s.NoError(err)

				sanitizedMap := map[string]any{}
				err = json.Unmarshal(tc.sanitizedPayload, &sanitizedMap)
				s.NoError(err)

				for _, f := range unallowedFields {
					_, ok := outputMap[f]
					s.Assert().False(ok)
				}

				s.Assert().Equal(outputMap, sanitizedMap)
			}
		})
	}
}

func (s *webhookSuite) Test_Work_ProperlyWorkJob() {
	tests := []struct {
		name                   string
		event                  string
		deliveryID             string
		payload                []byte
		loggings               []string
		notLoggings            []string
		setupMock              func(m mocks, payload []byte)
		err                    string
		shouldCreateCheckSuite bool
		isEnterprise           bool
	}{
		{
			name:    "Handle missing sender in push event",
			event:   "push",
			payload: fixture(s.T(), "push_missing_sender.json"),
			loggings: []string{
				"Body=\"skipping push event with missing sender\"",
			},
		},
		{
			name:    "Standard push example success",
			event:   "push",
			payload: fixture(s.T(), "push.json"),
			setupMock: func(m mocks, payload []byte) {
				m.invoker.EXPECT().Start(mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(nil)

				m.scheduleMngr.EXPECT().SyncOnPush(
					mock.Anything,
					types.GlobalID("R_kgDNA-c"),       // repo_global_id
					types.GitRef("refs/heads/master"), // ref
					mock.Anything,                     // actor
					mock.Anything,                     // owner_id
				).Return()
			},
			loggings: []string{
				"gh.launch.event.name=push",
				"gh.repo.global_id=R_kgDNA-c",
				"gh.launch.event.commit_sha=289345eeab3bfbf8a1651f9668cf5ca04dffa550",
				"gh.launch.event.ref=refs/heads/master",
				"gh.launch.pushed_at=2018-09-29T11:01:24",
				fmt.Sprintf("gh.launch.event.origin_time=%s", time.Now().UTC().Format("2006-01-02")),
				"gh.launch.event.is_rerun=false",
			},
			notLoggings: []string{
				"could not extract installation id",
			},
		},
		{
			name:    "Can determine a check suite rerun",
			event:   "check_suite",
			payload: fixture(s.T(), "check_suite_rerequested.json"),
			setupMock: func(m mocks, payload []byte) {
				m.invoker.EXPECT().Start(mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(nil)
				m.ghTwirp.EXPECT().GetActorsInfo(mock.Anything, []types.GlobalID{monalisaActorId}).Return(&ghtwirp.ActorsInfo{
					Actors: []*v1.Actor{{
						GlobalId: &v1.Identity{GlobalId: monalisaActorId.String()},
						IdString: monalisaLogin,
					}},
				}, nil)

				checkSuiteState := &types.CheckSuiteState{
					WorkflowFilePath:  ".github/workflows/test.yml",
					EventPayload:      payload,
					Event:             "check_suite",
					ExecutedAsActorID: monalisaActorId,
				}
				m.wbRepo.EXPECT().GetStateByCheckSuiteID(mock.Anything, mock.Anything).Return(checkSuiteState, true, nil)
			},
			loggings: []string{
				"re-run request received",
				"is_rerun=true",
			},
		},
		{
			name:    "Can determine a check suite rerun from a different actor",
			event:   "check_suite",
			payload: fixture(s.T(), "check_suite_rerequested.json"),
			setupMock: func(m mocks, payload []byte) {
				m.invoker.EXPECT().Start(mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(nil)
				// Return an updated ID when queried with legacy ID so we can ensure a next id lookup happens
				m.ghTwirp.EXPECT().GetActorsInfo(mock.Anything, []types.GlobalID{monalisaActorId}).Return(&ghtwirp.ActorsInfo{
					Actors: []*v1.Actor{{
						GlobalId: &v1.Identity{GlobalId: monalisaActorId.String()},
						IdString: monalisaLogin,
					}},
				}, nil)

				checkSuiteState := &types.CheckSuiteState{
					WorkflowFilePath:  ".github/workflows/test.yml",
					EventPayload:      payload,
					Event:             "check_suite",
					ExecutedAsActorID: monalisaActorId,
				}
				m.wbRepo.EXPECT().GetStateByCheckSuiteID(mock.Anything, mock.Anything).Return(checkSuiteState, true, nil)
			},
			loggings: []string{
				"re-run request received",
				"is_rerun=true",
			},
		},
		{
			name:    "Handles a repository event and skips cancelling workflows for non-enterprise",
			event:   "repository",
			payload: fixture(s.T(), "repository_event.json"),
			setupMock: func(m mocks, payload []byte) {
				m.scheduleMngr.EXPECT().NotifyRepository(mock.Anything, mock.MatchedBy(func(evt *launchtypes.NotifyRepositoryEvent) bool {
					return evt.RepositoryNodeId.GetGlobalId() == "R_kgDNA-c"
				})).Return(nil, nil)
			},
			loggings: []string{
				"skipping cancel all workflows in the repository",
			},
			isEnterprise: false,
		},
		{
			name:    "Handles a repository event by sending admin event to azp for enterprise",
			event:   "repository",
			payload: fixture(s.T(), "repository_event.json"),
			setupMock: func(m mocks, payload []byte) {
				m.scheduleMngr.EXPECT().NotifyRepository(mock.Anything, mock.MatchedBy(func(evt *launchtypes.NotifyRepositoryEvent) bool {
					return evt.RepositoryNodeId.GetGlobalId() == "R_kgDNA-c"
				})).Return(nil, nil)

				m.reporter.EXPECT().ReportRepoAdminEvent(mock.Anything,
					types.GlobalID("R_kgDNA-c"),
					adminevents.RepositoryDeleted, map[string]string{
						"repo_global_id":       "R_kgDNA-c",
						"repo_owner_global_id": "U_kgDOAP3FAg",
					}).Return(nil).Once()
			},
			loggings: []string{
				"gh.repo.global_id=R_kgDNA-c",
				"reporting repo admin event to cancel all workflows in the repository",
				"successfully reported admin event to cancel all workflows for repository",
			},
			isEnterprise: true,
		},
		{
			name:    "Handles a pull_request event, including running the `pull_request_target` synthetic event",
			event:   "pull_request",
			payload: fixture(s.T(), "pull_request_event.json"),
			setupMock: func(m mocks, payload []byte) {
				m.invoker.On("Start", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(nil)
			},
			loggings: []string{
				"gh.launch.event.name=pull_request ",
				"gh.launch.event.type=closed",
				"gh.launch.synthetic_event.name=pull_request_target ",
			},
			notLoggings: []string{
				"Missing value for observability key",
			},
		},
		{
			name:    "Errs on a job with no event specified",
			event:   "",
			payload: []byte("{}"),
			loggings: []string{
				"missing event from job",
			},
			err: "missing event from job",
		},
		{
			name:    "skips not allowed webhook event but does process it with NotifyRepository and skips cancelling workflows for non-enterprise",
			event:   "repository",
			payload: fixture(s.T(), "repository_event.json"),
			setupMock: func(m mocks, payload []byte) {
				m.scheduleMngr.On("NotifyRepository", mock.Anything, mock.MatchedBy(func(evt *launchtypes.NotifyRepositoryEvent) bool {
					return evt.RepositoryNodeId.GetGlobalId() == "R_kgDNA-c"
				})).Return(nil, nil)
			},
			loggings: []string{
				"skipping disallowed event",
				"skipping cancel all workflows in the repository",
			},
			isEnterprise: false,
		},
		{
			name:    "skips not allowed webhook event but does process it with NotifyRepository sending admin event for enterprise",
			event:   "repository",
			payload: fixture(s.T(), "repository_event.json"),
			setupMock: func(m mocks, payload []byte) {
				m.scheduleMngr.On("NotifyRepository", mock.Anything, mock.MatchedBy(func(evt *launchtypes.NotifyRepositoryEvent) bool {
					return evt.RepositoryNodeId.GetGlobalId() == "R_kgDNA-c"
				})).Return(nil, nil)

				m.reporter.On("ReportRepoAdminEvent", mock.Anything,
					types.GlobalID("R_kgDNA-c"),
					adminevents.RepositoryDeleted, map[string]string{
						"repo_global_id":       "R_kgDNA-c",
						"repo_owner_global_id": "U_kgDOAP3FAg",
					}).Return(nil).Once()
			},
			loggings: []string{
				"skipping disallowed event",
			},
			isEnterprise: true,
		},
		{
			name:    "skips robot app event for check_run",
			event:   "check_run",
			payload: fixture(s.T(), "robot_check_run.json"),
			loggings: []string{
				"skipping event from our own robot app",
			},
		},
		{
			name:    "skips robot app event for check_suite",
			event:   "check_suite",
			payload: fixture(s.T(), "robot_check_suite.json"),
			loggings: []string{
				"skipping event from our own robot app",
			},
		},
		{
			name:    "does not skip robot check_suite.rerequested for our own robot app",
			event:   "check_suite",
			payload: fixture(s.T(), "robot_check_suite_rerequested.json"),
			setupMock: func(m mocks, payload []byte) {
				m.invoker.On("Start", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(nil)
				m.ghTwirp.On("GetActorsInfo", mock.Anything, []types.GlobalID{monalisaActorId}).Return(&ghtwirp.ActorsInfo{
					Actors: []*v1.Actor{{
						GlobalId: &v1.Identity{GlobalId: monalisaActorId.String()},
						IdString: monalisaLogin,
					}},
				}, nil)

				checkSuiteState := &types.CheckSuiteState{
					WorkflowFilePath:  ".github/workflows/test.yml",
					EventPayload:      payload,
					Event:             "check_suite",
					ExecutedAsActorID: monalisaActorId,
				}
				m.wbRepo.On("GetStateByCheckSuiteID", mock.Anything, mock.Anything).Return(checkSuiteState, true, nil)
			},
			notLoggings: []string{
				"skipping event from our own robot app",
			},
		},
		{
			name:    "does not skip check_suite.rerequested for our own robot user",
			event:   "check_suite",
			payload: fixture(s.T(), "robot_user_check_suite_rerequested.json"),
			setupMock: func(m mocks, payload []byte) {
				m.invoker.On("Start", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(nil)
				m.ghTwirp.On("GetActorsInfo", mock.Anything, []types.GlobalID{monalisaActorId}).Return(&ghtwirp.ActorsInfo{
					Actors: []*v1.Actor{{
						GlobalId: &v1.Identity{GlobalId: monalisaActorId.String()},
						IdString: monalisaLogin,
					}},
				}, nil)

				checkSuiteState := &types.CheckSuiteState{
					WorkflowFilePath:  ".github/workflows/test.yml",
					EventPayload:      payload,
					Event:             "check_suite",
					ExecutedAsActorID: monalisaActorId,
				}
				m.wbRepo.On("GetStateByCheckSuiteID", mock.Anything, mock.Anything).Return(checkSuiteState, true, nil)
			},
			notLoggings: []string{
				"skipping event from our own robot user",
			},
		},
		{
			name:    "skips robot user event for issues",
			event:   "issues",
			payload: fixture(s.T(), "robot_issues_event.json"),
			loggings: []string{
				"skipping event from our own robot user",
			},
		},
		{
			name:    "skips check suite requested event",
			event:   "check_suite",
			payload: fixture(s.T(), "check_suite_requested_event.json"),
		},
		{
			name:    "skips the draft release event",
			event:   "release",
			payload: fixture(s.T(), "release_draft_event.json"),
			loggings: []string{
				"Skipping draft release event",
			},
		},
		{
			name:    "skips the branch delete push event",
			event:   "push",
			payload: fixture(s.T(), "push_event_branch_deleted.json"),
			setupMock: func(m mocks, payload []byte) {
				m.scheduleMngr.EXPECT().SyncOnPush(
					mock.Anything,
					types.GlobalID("R_kgDNA-c"),          // repo_global_id
					types.GitRef("refs/tags/simple-tag"), // ref
					mock.Anything,                        // actor
					mock.Anything,                        // owner_id
				).Return()
			},

			loggings: []string{
				"Skipping branch delete push event",
			},
		},
		{
			name:    "skips the ping event",
			event:   "ping",
			payload: []byte(`{"event": "ping"}`),
		},
		{
			name:    "Panic handling",
			event:   "push",
			payload: fixture(s.T(), "push.json"),
			setupMock: func(m mocks, payload []byte) {
				panicMsg := "panic!"
				m.invoker.On("Start", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).PanicMsg = &panicMsg
				m.scheduleMngr.EXPECT().SyncOnPush(
					mock.Anything,
					types.GlobalID("R_kgDNA-c"),       // repo_global_id
					types.GitRef("refs/heads/master"), // ref
					mock.Anything,                     // actor
					mock.Anything,                     // owner_id
				).Return()
			},
			err: "1 error occurred:\n\t* panic: panic!\n\n",
		},
		{
			name:    "log for workflow_run.completed event that is missing conclusion",
			event:   "workflow_run",
			payload: fixture(s.T(), "workflow_run_complete_no_conclusion.json"),
			setupMock: func(m mocks, payload []byte) {
				m.invoker.On("Start", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(nil)
			},
			loggings: []string{
				"missing conclusion for workflow_run.completed event",
			},
		},
		{
			name:    "Rate limiter allows push",
			event:   "push",
			payload: fixture(s.T(), "push.json"),
			setupMock: func(m mocks, payload []byte) {
				m.invoker.On("Start", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(nil)
				m.scheduleMngr.EXPECT().SyncOnPush(
					mock.Anything,
					types.GlobalID("R_kgDNA-c"),       // repo_global_id
					types.GitRef("refs/heads/master"), // ref
					mock.Anything,                     // actor
					mock.Anything,                     // owner_id
				).Return()
				m.ghTwirp.On("IsFeatureEnabledForRepository", mock.Anything, mock.Anything, mock.Anything).Unset()
				m.ghTwirp.On("IsFeatureEnabledForRepository", mock.Anything, ghclient.EnableWebhookRateLimitingDarkMode, mock.Anything).
					Return(func(ctx context.Context, featureFlagName string, repoID int64) bool {
						return true
					}, nil).Maybe()
				s.m.webhookRateLimiter.On("Allow", mock.Anything, mock.Anything).Return(true)
			},
			loggings: []string{
				"gh.launch.event.name=push",
				"gh.repo.global_id=R_kgDNA-c",
				"gh.launch.event.commit_sha=289345eeab3bfbf8a1651f9668cf5ca04dffa550",
				"gh.launch.event.ref=refs/heads/master",
				"gh.launch.pushed_at=2018-09-29T11:01:24",
				fmt.Sprintf("gh.launch.event.origin_time=%s", time.Now().UTC().Format("2006-01-02")),
				"gh.launch.event.is_rerun=false",
			},
			notLoggings: []string{
				"could not extract installation id",
			},
		},
		{
			name:    "Rate limiter denies push",
			event:   "push",
			payload: fixture(s.T(), "push.json"),
			setupMock: func(m mocks, payload []byte) {
				m.invoker.On("Start", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Unset()
				m.scheduleMngr.EXPECT().SyncOnPush(
					mock.Anything,
					mock.Anything,
					mock.Anything,
					mock.Anything,
					mock.Anything,
				).Unset()
				m.ghTwirp.On("IsFeatureEnabledForRepository", mock.Anything, mock.Anything, mock.Anything).Unset()
				m.ghTwirp.On("IsFeatureEnabledForRepository", mock.Anything, ghclient.EnableWebhookRateLimitingDarkMode, mock.Anything).
					Return(true)
				s.m.webhookRateLimiter.On("Allow", mock.Anything, mock.Anything).Return(false)
			},
			loggings:    []string{},
			notLoggings: []string{},
			err:         (&rate.QueueRateLimitError{}).Error(),
		},
	}

	for _, tc := range tests {
		s.Run(tc.name, func() {
			s.SetupTest() // Need to reset the mocks for this subtest

			ctx := reqmeta.WithRequestMetadata(context.Background(), reqmeta.NewRequestMetadata())
			ctx = context.WithValue(
				ctx,
				mureqmeta.RMDContextKey,
				mureqmeta.NewRequestMetadata())

			logger := testutils.NewRecordingLogger()

			var deliveryID string
			if tc.deliveryID != "" {
				deliveryID = tc.deliveryID
			} else {
				deliveryUUID, _ := uuid.NewUUID()
				deliveryID = deliveryUUID.String()
			}

			ctx = deliveryguid.WithDeliveryGUID(ctx, &deliveryID)
			guidTime, err := deliveryguid.ExtractTime(deliveryID)
			s.NoError(err)
			enqueuedAt := guidTime.Unix() * 1000

			job := Job{
				WebhookDeliveryID: deliveryID,
				Event:             tc.event,
				EnqueuedAt:        enqueuedAt,
				RawPayload:        (*json.RawMessage)(&tc.payload),
			}

			cfg := &Config{
				AppID:             int64(15368), // Our App, as seen in the fixture data
				ActionsAppIDs:     []int64{int64(15368), int64(testRobotAppID)},
				ActionsBotNodeIDs: []types.GlobalID{types.GlobalID(testRobotNodeID)}, // Our Bot ID, as seen in the fixture data
				IsEnterprise:      tc.isEnterprise,
			}

			if tc.setupMock != nil {
				tc.setupMock(s.m, tc.payload)
			}

			sloReporter := slometrics.New(s.m.hydroEmitter)

			labeler := customerlabels.NewNoopCustomerLabeler()

			obs := observability.New(logger.Logger, statter.NullStatter())
			obs.AddCheckpoint(observability.AqJobRecvAtCheckpoint, time.Now())

			p := New(cfg, s.m.invoker, s.m.wbRepo, s.m.scheduleMngr, s.m.ghTwirp, s.m.reporter, sloReporter, labeler, s.m.webhookRateLimiter)
			jobPayload, _ := json.Marshal(job)

			err = p.Process(ctx, obs, jobPayload, tc.shouldCreateCheckSuite)

			if len(tc.err) > 0 {
				s.Contains(err.Error(), tc.err)
			} else {
				s.NoError(err)
			}

			for _, msg := range tc.loggings {
				s.assertLogged(logger, msg)
			}

			for _, msg := range tc.notLoggings {
				s.assertNotLogged(logger, msg)
			}
		})
	}
}

func Test_Process_GitHubTenant(t *testing.T) {
	tenantID := int64(1234)
	tenantIDHeaderVal := "1234"
	tenantSlug := "slug"

	tests := []struct {
		name                     string
		isMultiTenant            bool
		headers                  []header
		shouldErr                bool
		expectedGitHubTenantID   int64
		expectedGitHubTenantSlug string
	}{
		{
			name: "non-multi-tenant/no-headers",
		},
		{
			name: "non-multi-tenant/with-headers",
			headers: []header{
				{
					ghtenant.GitHubTenantHeader: tenantSlug,
				},
				{
					ghtenant.GitHubTenantIDHeader: tenantIDHeaderVal,
				},
			},
		},
		{
			name:          "multi-tenant/tenant-id-and-slug-header",
			isMultiTenant: true,
			headers: []header{
				{
					ghtenant.GitHubTenantHeader: tenantSlug,
				},
				{
					ghtenant.GitHubTenantIDHeader: tenantIDHeaderVal,
				},
			},
			expectedGitHubTenantID:   tenantID,
			expectedGitHubTenantSlug: tenantSlug,
		},
		{
			name:          "multi-tenant/missing-tenant-id-header",
			isMultiTenant: true,
			headers: []header{
				{
					ghtenant.GitHubTenantHeader: tenantSlug,
				},
			},
			shouldErr: true,
		},
		{
			name:          "multi-tenant/missing-tenant-slug-header",
			isMultiTenant: true,
			headers: []header{
				{
					ghtenant.GitHubTenantIDHeader: tenantIDHeaderVal,
				},
			},
			shouldErr: true,
		},
		{
			name:          "multi-tenant/tenant-id-header-not-int",
			isMultiTenant: true,
			headers: []header{
				{
					ghtenant.GitHubTenantHeader: tenantSlug,
				},
				{
					ghtenant.GitHubTenantIDHeader: "not-an-int",
				},
			},
			shouldErr: true,
		},
		{
			name:          "multi-tenant/malformed-headers",
			isMultiTenant: true,
			headers: []header{
				{
					"": "",
				},
				{
					"": "",
				},
			},
			shouldErr: true,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			r := require.New(t)

			invoker := &workflowinvoker.MockInvoker{}
			wbRepo := &deployer.MockWorkflowBuildsRepository{}
			scheduleMngr := &schedulemanager.MockManager{}
			reporter := &adminevents.MockReporter{}
			hydroEmitter := &slometrics.MockHydroEmitter{}
			ghTwirp := &ghtwirp.MockClient{}

			hydroEmitter.On("EmitQueueRun", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(nil)

			sloReporter := slometrics.New(hydroEmitter)
			labeler := customerlabels.NewNoopCustomerLabeler()
			webhookRateLimiter := &rate.NullRateLimiter{}

			invoker.On("Start",
				mock.Anything,
				mock.Anything,
				mock.Anything,
				mock.Anything,
				mock.Anything,
			).Return(nil).Run(func(args mock.Arguments) {
				inv := args.Get(2).(workflowinvoker.Invocation)
				r.EqualValues(tc.expectedGitHubTenantID, inv.Target.GitHubTenant.ID)
				r.EqualValues(tc.expectedGitHubTenantSlug, inv.Target.GitHubTenant.Slug)
			})

			scheduleMngr.EXPECT().SyncOnPush(
				mock.Anything,
				mock.Anything,
				mock.Anything,
				mock.Anything,
				mock.Anything,
			).Return()

			ghTwirp.On("GetNextGlobalID", mock.Anything, mock.Anything).
				Return(func(ctx context.Context, globalID string) types.GlobalID {
					assert.True(t, types.IsNextGlobalID(globalID), "%s is not a global next ID", globalID)
					return types.GlobalID(globalID)
				}, nil).Maybe()

			ghTwirp.On("IsFeatureEnabledForRepository", mock.Anything, mock.Anything, mock.Anything).
				Return(func(ctx context.Context, featureFlagName string, repoID int64) bool {
					return false
				}, nil).Maybe()

			cfg := Config{
				AppID:             int64(15368),
				ActionsAppIDs:     []int64{int64(15368), int64(testRobotAppID)},
				ActionsBotNodeIDs: []types.GlobalID{types.GlobalID(testRobotNodeID)},
				IsMultiTenant:     tc.isMultiTenant,
			}

			p := New(&cfg, invoker, wbRepo, scheduleMngr, ghTwirp, reporter, sloReporter, labeler, webhookRateLimiter)

			obs := observability.NewNullObservability()

			deliveryUUID, _ := uuid.NewUUID()
			rawPayload := fixture(t, "pull_request_event.json")
			messagePayload := Job{
				WebhookDeliveryID: deliveryUUID.String(),
				Event:             "pull_request",
				RawPayload:        (*json.RawMessage)(&rawPayload),
				WebhookMetadata: &metadata{
					Headers: tc.headers,
				},
			}

			messagePayloadBytes, err := json.Marshal(messagePayload)
			r.NoError(err)

			err = p.Process(context.Background(), obs, messagePayloadBytes, false)

			// Ensure that we emit a QueueRunFailure Event when encountering an error during the extraction of the tenant header
			if tc.shouldErr {
				// setup the msg we're expecting
				newPayload, _ := globalidmigration.ConvertPayloadIDs(context.Background(), obs, p.ghtwirp,
					"webhook.processor.process", *messagePayload.RawPayload)
				jsonEvent, _ := unmarshalWebhook(newPayload)
				msg := queueRunMessage(context.Background(), obs, messagePayload.Event, jsonEvent)
				msg.Status = hydroV0.QueueRun_FAILURE
				msg.ErrorMessage = "ExtractTenantIdFromJob"

				assert.True(t, hydroEmitter.AssertCalled(t, "EmitQueueRun", msg))
				r.Error(err)
				return
			}

			r.NoError(err)
		})
	}
}

func (s *webhookSuite) assertLogged(logger testutils.RecordingLogger, message string) {
	s.Require().Contains(logger.String(), message, fmt.Sprintf("\nOutput:\n%s\nShould contain:\n%s", logger.String(), message))
}

func (s *webhookSuite) assertNotLogged(logger testutils.RecordingLogger, message string) {
	s.Require().NotContains(logger.String(), message, fmt.Sprintf("\nOutput:\n%s\nShould not contain:\n%s", logger.String(), message))
}

func fixture(t *testing.T, name string) []byte {
	data, err := os.ReadFile(filepath.Join("fixtures", name))
	require.NoError(t, err, "Reading %s fixture should not error", name)
	return data
}
