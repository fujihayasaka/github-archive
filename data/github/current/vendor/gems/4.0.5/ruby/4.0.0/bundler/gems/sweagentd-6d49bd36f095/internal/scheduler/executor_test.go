package scheduler

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/aqueduct"
	"github.com/github/sweagentd/internal/automations"
	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/customagent"
	"github.com/github/sweagentd/internal/customagent/customagenttest"
	"github.com/github/sweagentd/internal/experiments"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/jobs/store/memory"
	"github.com/github/sweagentd/internal/jobservice"
	jobLimiter "github.com/github/sweagentd/internal/limiter"
	"github.com/github/sweagentd/internal/observability"
	schedulerstore "github.com/github/sweagentd/internal/scheduler/store"
	"github.com/github/sweagentd/internal/spokes/spokestest"
	"github.com/github/sweagentd/internal/sweagentd"
	sweagentdtwirp "github.com/github/sweagentd/proto/sweagentd/v1"
	gogithub "github.com/google/go-github/v75/github"
	"github.com/stretchr/testify/require"
)

const (
	execTestAutomationID = "auto-uuid-1"
	execTestRepoID       = int64(1234)
	execTestOwnerID      = int64(5678)
)

// stubExecutorFF lets each test enable / disable individual flags.
type stubExecutorFF struct {
	flags map[string]bool
}

func (s *stubExecutorFF) IsEnabledForRepoOrOwner(ctx context.Context, name string, repo sweagentd.Repository) bool {
	return s.IsEnabledForRepoOrOwnerWithDefaultValue(ctx, name, false, repo)
}

func (s *stubExecutorFF) IsEnabledForRepoOrOwnerWithDefaultValue(_ context.Context, name string, defaultValue bool, _ sweagentd.Repository) bool {
	enabled, ok := s.flags[name]
	if !ok {
		return defaultValue
	}
	return enabled
}

// stubLookup records ListForEvent calls and returns canned responses.
type stubLookup struct {
	listResp []automations.RuntimeConfig
	listErr  error

	listCalls []automations.ListForEventRequest
}

func (s *stubLookup) HasActiveForEvent(_ context.Context, _ automations.EventMatchRequest) (bool, error) {
	return false, nil
}
func (s *stubLookup) ListForEvent(_ context.Context, req automations.ListForEventRequest) ([]automations.RuntimeConfig, error) {
	s.listCalls = append(s.listCalls, req)
	return s.listResp, s.listErr
}
func (s *stubLookup) AutomationsDisabledFromConfig(_ context.Context, _ *sweagentdtwirp.ConfigurationForRepositoryResponse, _ int64, _ string) bool {
	return false
}

// counterRecorder captures stats counter calls so tests can assert metric emissions.
type counterRecorder struct {
	stats.NullClient

	calls []counterEntry
}

type counterEntry struct {
	key  string
	tags stats.Tags
}

type publicRepoClient struct {
	*github.NoopClient
}

func (c *publicRepoClient) GetRepositoryByID(ctx context.Context, id int64) (*gogithub.Repository, error) {
	repo, err := c.NoopClient.GetRepositoryByID(ctx, id)
	if err != nil {
		return nil, err
	}
	repo.Visibility = gogithub.Ptr("public")
	return repo, nil
}

func (c *counterRecorder) Counter(key string, tags stats.Tags, _ int64) {
	c.calls = append(c.calls, counterEntry{key: key, tags: tags})
}

func (c *counterRecorder) findByKey(key string) []counterEntry {
	var out []counterEntry
	for _, e := range c.calls {
		if e.key == key {
			out = append(out, e)
		}
	}
	return out
}

// newExecutorForTest builds a minimal Executor wired with stubs.
func newExecutorForTest(t *testing.T, ff *stubExecutorFF, lookup automations.Lookup, statter stats.Client) *Executor {
	obsv := observability.NewNoopExporters()
	if statter != nil {
		obsv.Statter = statter
	}
	return &Executor{
		ffClient:         ff,
		automationLookup: lookup,
		ghFactory:        &github.NoopClientFactory{},
		appProvider:      agenticapptest.NewTestProvider(t),
		obsv:             obsv,
	}
}

func cmcSourcedTrigger() *schedulerstore.IntervalTriggerRecord {
	// Mirrors what the reconciler writes: numeric IDs populated, repo
	// owner login / name left empty (resolved at fire time).
	return &schedulerstore.IntervalTriggerRecord{
		ID:            "trigger-1",
		Scope:         schedulerstore.ScopeRepository,
		ScopeID:       execTestRepoID,
		AgentID:       execTestAutomationID,
		IntervalType:  schedulerstore.IntervalTypeDaily,
		ScatterOffset: 0.5,
		ActorID:       42,
		ActorLogin:    "automation-owner",
		RepoID:        execTestRepoID,
		RepoOwnerID:   execTestOwnerID,
	}
}

// TestExecute_LookupHasNoMatch verifies the executor silently skips when the
// automation isn't in CMC's active list.
func TestExecute_LookupHasNoMatch(t *testing.T) {
	statter := &counterRecorder{}
	lookup := &stubLookup{listResp: nil} // empty list — automation no longer active
	ff := &stubExecutorFF{flags: map[string]bool{
		featureflags.CopilotSWEAgentCustomAgentTriggers: true,
	}}
	e := newExecutorForTest(t, ff, lookup, statter)

	err := e.Execute(context.Background(), cmcSourcedTrigger())
	require.NoError(t, err, "missing CMC automation must skip silently, not error")

	require.Len(t, lookup.listCalls, 1, "exactly one CMC lookup expected")
	require.Equal(t, automations.EventInterval, lookup.listCalls[0].Event.EventName)
	require.Equal(t, execTestRepoID, lookup.listCalls[0].Event.RepoID)
	require.Equal(t, execTestOwnerID, lookup.listCalls[0].Event.OwnerID)
	require.Equal(t, "test-owner", lookup.listCalls[0].Repo.OwnerLogin, "RepoInfo must be populated from GH API")
	require.Equal(t, "test-repo", lookup.listCalls[0].Repo.RepoName, "RepoInfo must be populated from GH API")

	require.NotEmpty(t, statter.findByKey("triggers.skipped"))
	for _, c := range statter.findByKey("triggers.skipped") {
		require.Equal(t, "cmc_automation_missing", c.tags["reason"])
	}
}

// TestExecute_LookupErrorPropagates ensures lookup errors are surfaced so the
// scheduler tick fails and the schedule does not advance.
func TestExecute_LookupErrorPropagates(t *testing.T) {
	statter := &counterRecorder{}
	lookupErr := errors.New("twirp: deadline exceeded")
	lookup := &stubLookup{listErr: lookupErr}
	ff := &stubExecutorFF{flags: map[string]bool{
		featureflags.CopilotSWEAgentCustomAgentTriggers: true,
	}}
	e := newExecutorForTest(t, ff, lookup, statter)

	err := e.Execute(context.Background(), cmcSourcedTrigger())
	require.Error(t, err)
	require.Contains(t, err.Error(), "failed to look up CMC automation config")
	require.Empty(t, statter.findByKey("triggers.job_error"), "executor should let scheduler emit the single job_error metric")

	var taggedErr *triggerJobError
	require.True(t, errors.As(err, &taggedErr), "lookup error should carry a job_error reason for scheduler telemetry")
	require.Equal(t, "cmc_lookup_error", taggedErr.reason)
}

// TestExecute_NilLookup_SkipsSafely covers the defensive nil-lookup path: skip
// with a metric, don't panic.
func TestExecute_NilLookup_SkipsSafely(t *testing.T) {
	statter := &counterRecorder{}
	ff := &stubExecutorFF{flags: map[string]bool{}}
	e := newExecutorForTest(t, ff, nil, statter)

	err := e.Execute(context.Background(), cmcSourcedTrigger())
	require.NoError(t, err)
	skipped := statter.findByKey("triggers.skipped")
	require.NotEmpty(t, skipped)
	found := false
	for _, c := range skipped {
		if c.tags["reason"] == "no_cmc_lookup" {
			found = true
			break
		}
	}
	require.True(t, found, "expected a triggers.skipped with reason=no_cmc_lookup")
}

// TestExecute_MasterFFOff_SkipsBeforeLookup verifies the master kill switch
// short-circuits before the CMC lookup is called (cost saving on FF-off repos).
func TestExecute_MasterFFOff_SkipsBeforeLookup(t *testing.T) {
	statter := &counterRecorder{}
	lookup := &stubLookup{}
	ff := &stubExecutorFF{flags: map[string]bool{
		// CopilotSWEAgentCustomAgentTriggers off — master kill switch.
	}}
	e := newExecutorForTest(t, ff, lookup, statter)

	err := e.Execute(context.Background(), cmcSourcedTrigger())
	require.NoError(t, err)
	require.Empty(t, lookup.listCalls, "lookup must not be called when master FF is off")

	skipped := statter.findByKey("triggers.skipped")
	require.NotEmpty(t, skipped)
	found := false
	for _, c := range skipped {
		if c.tags["reason"] == "feature_flag" {
			found = true
			break
		}
	}
	require.True(t, found, "expected a triggers.skipped with reason=feature_flag")
}

func TestExecute_PublicRepositorySkipsBeforeLookup(t *testing.T) {
	statter := &counterRecorder{}
	lookup := &stubLookup{}
	ff := &stubExecutorFF{flags: map[string]bool{
		featureflags.CopilotSWEAgentCustomAgentTriggers: true,
	}}
	e := newExecutorForTest(t, ff, lookup, statter)
	e.ghFactory = &github.NoopClientFactory{
		MockNewClientFromRepo: func(context.Context, int64, int64) (github.ClientInterface, error) {
			return &publicRepoClient{NoopClient: &github.NoopClient{}}, nil
		},
	}

	err := e.Execute(context.Background(), cmcSourcedTrigger())
	require.NoError(t, err)
	require.Empty(t, lookup.listCalls, "lookup must not be called for public repositories")

	skipped := statter.findByKey("triggers.skipped")
	require.NotEmpty(t, skipped)
	found := false
	for _, c := range skipped {
		if c.tags["reason"] == "public_repository" {
			found = true
			break
		}
	}
	require.True(t, found, "expected a triggers.skipped with reason=public_repository")
}

func TestExecute_PublicRepositoryFlagDisabledProceeds(t *testing.T) {
	statter := &counterRecorder{}
	lookup := &stubLookup{}
	ff := &stubExecutorFF{flags: map[string]bool{
		featureflags.CopilotSWEAgentCustomAgentTriggers: true,
		featureflags.CopilotAutomationsBlockPublicRepos: false,
	}}
	e := newExecutorForTest(t, ff, lookup, statter)
	e.ghFactory = &github.NoopClientFactory{
		MockNewClientFromRepo: func(context.Context, int64, int64) (github.ClientInterface, error) {
			return &publicRepoClient{NoopClient: &github.NoopClient{}}, nil
		},
	}

	err := e.Execute(context.Background(), cmcSourcedTrigger())
	require.NoError(t, err)
	require.Len(t, lookup.listCalls, 1, "lookup must be called when public-repo block is disabled")

	for _, c := range statter.findByKey("triggers.skipped") {
		require.NotEqual(t, "public_repository", c.tags["reason"])
	}
}

func TestExecute_AutomationOwnerNeedsWriteAccess(t *testing.T) {
	statter := &counterRecorder{}
	lookup := &stubLookup{
		listResp: []automations.RuntimeConfig{{
			AutomationID: execTestAutomationID,
			CustomAgent: customagent.NewWithConfig(
				customagent.Metadata{Name: "test-automation-agent", RepoID: execTestRepoID, RepoOwnerID: execTestOwnerID},
				customagent.NewConfigWithAttributes(customagent.ConfigAttributes{DisplayName: "Test Automation Agent"}),
			),
		}},
	}
	ff := &stubExecutorFF{flags: map[string]bool{
		featureflags.CopilotSWEAgentCustomAgentTriggers: true,
	}}
	e := newExecutorForTest(t, ff, lookup, statter)
	trigger := cmcSourcedTrigger()
	trigger.ActorLogin = "automation-owner-read"

	err := e.Execute(context.Background(), trigger)
	require.NoError(t, err)

	skipped := statter.findByKey("triggers.skipped")
	require.NotEmpty(t, skipped)
	found := false
	for _, c := range skipped {
		if c.tags["reason"] == triggerSkipReasonAutomationOwnerWrite {
			found = true
			break
		}
	}
	require.True(t, found, "expected a triggers.skipped with reason=automation_owner_write")
}

// TestExecute_Build_PassesMatchedCustomAgent is the happy-path regression
// test ensuring matched.CustomAgent flows onto the resulting job. The other
// tests short-circuit before Build(), so this is the only one that
// catches a missing WithCustomAgent / WithAgentID wiring.
func TestExecute_Build_PassesMatchedCustomAgent(t *testing.T) {
	const automationAgentName = "test-automation-agent"
	const expectedAppID = int64(31337)

	obsv := observability.NewNoopExporters()

	// GitHub client / factory: NoopClient.GetRepositoryByID returns a fully
	// populated *gg.Repository, which is what Execute needs after step 7.
	defaultGH := &github.NoopClient{}
	defaultGHF := &github.NoopClientFactory{
		MockNewClient: func(_ string) github.ClientInterface {
			return defaultGH
		},
		GitHubAppLogin: "github-copilot",
		GitHubBotLogin: "github-copilot-bot",
	}

	// Twirp / customagent / agenticapp deps required by jobservice.New.
	mockGhTwirp := &githubtwirp.NoopClient{
		NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
			ConfigurationForRepositoryResponse: &sweagentdtwirp.ConfigurationForRepositoryResponse{
				IsAgentEnabled: true,
			},
		},
	}
	caSvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), githubtwirp.NewNoopClient(), featureflags.NewNoopClient(nil))
	appProvider := agenticapptest.NewTestProviderWithID(t, expectedAppID)

	// FF set: master + UseAsyncSessions on so Build() runs without reaching
	// capi session creation. interval-disable kept off.
	ffClient := featureflags.NewNoopClient(map[string]bool{
		featureflags.CopilotSWEAgentCustomAgentTriggers:                true,
		featureflags.CopilotSWEAgentUseAsyncSessions:                   true,
		featureflags.CopilotSWEAgentCustomAgentTriggersDisableInterval: false,
	})

	jobStore := memory.NewStore()
	countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Hour)
	limiter := jobLimiter.NewJobLimiter(jobStore, countTracker, nil)
	exp := experiments.NewNoopClient()
	aq := aqueduct.NewMemoryClient(obsv)
	jobSvc := jobservice.New(
		obsv, ffClient, jobStore, capi.NewNoopClient(), defaultGHF, mockGhTwirp,
		aq, limiter, exp, caSvc, "test_name", "test@example.com",
		spokestest.NewClient(t), appProvider, nil,
	)

	// Build the matched custom agent. This is what the reconciler's CMC
	// lookup would produce after parsing an automation record from CMC.
	matchedAgent := customagent.NewWithConfig(
		customagent.Metadata{
			Name:        automationAgentName,
			RepoID:      execTestRepoID,
			RepoOwnerID: execTestOwnerID,
		},
		customagent.NewConfigWithAttributes(customagent.ConfigAttributes{
			DisplayName: "Test Automation Agent",
			Description: "Custom agent backing this automation",
			Tools:       []string{"*"},
		}),
	)

	lookup := &stubLookup{
		listResp: []automations.RuntimeConfig{{
			AutomationID: execTestAutomationID,
			CustomAgent:  matchedAgent,
		}},
	}

	e := &Executor{
		ffClient:         ffClient,
		automationLookup: lookup,
		ghFactory:        defaultGHF,
		appProvider:      appProvider,
		jobSvc:           jobSvc,
		obsv:             obsv,
		// checker intentionally nil: it is gated by an explicit nil-check.
	}

	err := e.Execute(context.Background(), cmcSourcedTrigger())
	require.NoError(t, err, "happy-path Execute must succeed")

	// Fetch the persisted job and verify matched.CustomAgent reached the job
	// (i.e. WithCustomAgent / WithAgentID are wired correctly).
	jobsList, err := jobStore.GetJobs(context.Background(), execTestOwnerID, execTestRepoID)
	require.NoError(t, err)
	require.Len(t, jobsList, 1, "Execute must persist exactly one job")
	job := jobsList[0]

	require.Equal(t, automationAgentName, job.CustomAgent.Name,
		"job.CustomAgent.Name must equal matched.CustomAgent.Name() — if this fails, the builder chain is missing WithCustomAgent(matched.CustomAgent)")
	require.Equal(t, expectedAppID, job.AgentID,
		"job.AgentID must equal app.AppID() — if this fails, the builder chain is missing WithAgentID(app.AppID())")
	require.Equal(t, execTestAutomationID, job.AutomationID,
		"job.AutomationID must equal trigger.AgentID — confirms WithAutomationID is still wired")
	require.True(t, job.HasCustomAgent(),
		"job.HasCustomAgent() must be true — the assignment's CustomAgent.Name drives downstream customAgentSvc.FromDB resolution")
}
