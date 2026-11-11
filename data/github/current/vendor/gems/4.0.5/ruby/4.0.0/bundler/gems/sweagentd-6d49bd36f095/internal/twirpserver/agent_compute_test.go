package twirpserver

import (
	"context"
	"errors"
	"testing"
	"time"

	aqueductapi "github.com/github/aqueduct-client-go/v3/pkg/aqueduct"
	repositoriesTwirp "github.com/github/github-proto/gen/go/repositories/v1"
	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	aqueductJobs "github.com/github/sweagentd/internal/aqueduct/jobs"
	"github.com/github/sweagentd/internal/cache"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/sandbox"
	"github.com/github/sweagentd/internal/sandbox/stopguard"
	"github.com/github/sweagentd/internal/sweagentd"
	jobs_pb "github.com/github/sweagentd/proto/jobs/v1"
	sweagentdTwirp "github.com/github/sweagentd/proto/sweagentd/v1"
	gg "github.com/google/go-github/v75/github"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
	"google.golang.org/protobuf/types/known/durationpb"
)

// fakeSandbox is a stub sandboxOps used in tests. The zero value returns nil
// from every method.
type fakeSandbox struct{}

func (fakeSandbox) CreateSandbox(_ context.Context, _ *sandbox.CreateSandboxParams) (*sandbox.CreateSandboxResult, error) {
	return &sandbox.CreateSandboxResult{}, nil
}
func (fakeSandbox) StopSandbox(_ context.Context, _ string, _ uint64) error   { return nil }
func (fakeSandbox) ResumeSandbox(_ context.Context, _ string, _ uint64) error { return nil }
func (fakeSandbox) DeleteSandbox(_ context.Context, _ string, _ uint64) error { return nil }
func (fakeSandbox) GetSandboxState(_ context.Context, _ string, _ uint64) (string, error) {
	return "suspended", nil
}
func (fakeSandbox) GetSandboxInfo(_ context.Context, _ string, _ uint64) (*sandbox.Info, error) {
	return &sandbox.Info{RepositoryID: 1, AgentID: 1}, nil
}
func (fakeSandbox) ResumeCopilotCLI(_ context.Context, _ string, _ uint64, _ string, _ map[string]string) error {
	return nil
}

type trackingSandbox struct {
	stopCalls          int
	lastComputeID      string
	lastActorID        uint64
	stopErr            error
	resumeErr          error
	stateValue         string
	stateErr           error
	stateCalls         int
	getInfoResp        *sandbox.Info
	getInfoErr         error
	getInfoCalls       int
	resumeCLIErr       error
	resumeCLICalls     int
	resumeCLILastEnv   map[string]string
	resumeCLILastRepo  string
	resumeCLILastID    string
	resumeCLILastActor uint64
	resumeCalls        int
}

func (s *trackingSandbox) CreateSandbox(_ context.Context, _ *sandbox.CreateSandboxParams) (*sandbox.CreateSandboxResult, error) {
	return &sandbox.CreateSandboxResult{}, nil
}

func (s *trackingSandbox) StopSandbox(_ context.Context, sandboxID string, actorID uint64) error {
	s.stopCalls++
	s.lastComputeID = sandboxID
	s.lastActorID = actorID
	return s.stopErr
}

func (s *trackingSandbox) ResumeSandbox(_ context.Context, _ string, _ uint64) error {
	s.resumeCalls++
	return s.resumeErr
}
func (s *trackingSandbox) DeleteSandbox(_ context.Context, _ string, _ uint64) error { return nil }

func (s *trackingSandbox) GetSandboxState(_ context.Context, _ string, _ uint64) (string, error) {
	s.stateCalls++
	if s.stateErr != nil {
		return "", s.stateErr
	}
	// Default to "suspended" so unconfigured tests reach the full-resume
	// path that the existing PR #13074 cases were written against.
	state := s.stateValue
	if state == "" {
		state = "suspended"
	}
	return state, nil
}

func (s *trackingSandbox) GetSandboxInfo(_ context.Context, _ string, _ uint64) (*sandbox.Info, error) {
	s.getInfoCalls++
	if s.getInfoErr != nil {
		return nil, s.getInfoErr
	}
	if s.getInfoResp != nil {
		return s.getInfoResp, nil
	}
	return &sandbox.Info{RepositoryID: 1, AgentID: 1}, nil
}

func (s *trackingSandbox) ResumeCopilotCLI(_ context.Context, sandboxID string, actorID uint64, repoNWO string, freshEnv map[string]string) error {
	s.resumeCLICalls++
	s.resumeCLILastID = sandboxID
	s.resumeCLILastActor = actorID
	s.resumeCLILastRepo = repoNWO
	s.resumeCLILastEnv = freshEnv
	return s.resumeCLIErr
}

type mockAqueductClient struct {
	scheduledJobs []sweagentd.AqueductJob
	scheduledAt   []time.Time
	scheduleErr   error
}

func (m *mockAqueductClient) AppName() string                    { return "test-app" }
func (m *mockAqueductClient) AqueductURL() string                { return "http://aqueduct.invalid" }
func (m *mockAqueductClient) InternalClient() aqueductapi.Client { return nil }
func (m *mockAqueductClient) QueueJob(_ context.Context, _ sweagentd.AqueductJob) (string, error) {
	return "", nil
}
func (m *mockAqueductClient) ScheduleJob(_ context.Context, job sweagentd.AqueductJob, deliverAt time.Time) (string, error) {
	m.scheduledJobs = append(m.scheduledJobs, job)
	m.scheduledAt = append(m.scheduledAt, deliverAt)
	if m.scheduleErr != nil {
		return "", m.scheduleErr
	}
	return "scheduled-job-id", nil
}
func (m *mockAqueductClient) RequeueJob(_ context.Context, _ sweagentd.AqueductJob) (string, error) {
	return "", nil
}
func (m *mockAqueductClient) RequeueJobWithDelay(_ context.Context, _ sweagentd.AqueductJob, _ time.Duration) (string, error) {
	return "", nil
}
func (m *mockAqueductClient) QueueDepth(_ context.Context, _ string) (int64, error) { return 0, nil }

func TestCreateAgentCompute_ValidationErrors(t *testing.T) {
	server := &Server{
		obsv: observability.NewNoopExporters(),
	}

	tests := []struct {
		name    string
		req     *jobs_pb.CreateAgentComputeRequest
		wantArg string
	}{
		{
			name:    "missing scope_id when repository_id is unset",
			req:     &jobs_pb.CreateAgentComputeRequest{ActorId: 1, AgentId: 1},
			wantArg: "scope_id",
		},
		{
			name:    "missing repository_owner_id when repository_id is set",
			req:     &jobs_pb.CreateAgentComputeRequest{RepositoryId: 42, ActorId: 1, AgentId: 1},
			wantArg: "repository_owner_id",
		},
		{
			name:    "missing actor_id",
			req:     &jobs_pb.CreateAgentComputeRequest{RepositoryId: 42, RepositoryOwnerId: 1, AgentId: 1},
			wantArg: "actor_id",
		},
		{
			name:    "missing agent_id",
			req:     &jobs_pb.CreateAgentComputeRequest{RepositoryId: 42, RepositoryOwnerId: 1, ActorId: 1},
			wantArg: "agent_id",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := server.CreateAgentCompute(context.Background(), tt.req)
			require.Error(t, err)
			var twerr twirp.Error
			require.True(t, errors.As(err, &twerr))
			assert.Equal(t, twirp.InvalidArgument, twerr.Code())
			assert.Contains(t, twerr.Msg(), tt.wantArg)
		})
	}
}

func TestCreateAgentComputeFetchesSetupDataConcurrently(t *testing.T) {
	started := make(chan string, 3)
	release := make(chan struct{})
	block := func(name string) {
		started <- name
		<-release
	}

	ghTwirp := githubtwirp.NewNoopClient()
	ghTwirp.NoopRepositoriesAPI.MockFindRepositories = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesRequest) (*repositoriesTwirp.FindRepositoriesResponse, error) {
		block("repo")
		return &repositoriesTwirp.FindRepositoriesResponse{
			Repositories: []*repositoriesTwirp.RepositoryListItem{{
				Id:         req.GetIds()[0],
				OwnerLogin: "owner",
				Name:       "repo",
			}},
		}, nil
	}
	ghTwirp.NoopSweagentdAPI.MockConfigurationForRepository = func(ctx context.Context, req *sweagentdTwirp.ConfigurationForRepositoryRequest) (*sweagentdTwirp.ConfigurationForRepositoryResponse, error) {
		block("config")
		return &sweagentdTwirp.ConfigurationForRepositoryResponse{
			IsFirewallEnabled:             true,
			ShouldFirewallUseDefaultRules: true,
			FirewallAllowedRules:          []string{"api.example.com"},
		}, nil
	}
	ghTwirp.NoopSweagentdAPI.MockMintUserToServerTokenForRepos = func(ctx context.Context, req *sweagentdTwirp.MintUserToServerTokenForReposRequest) (*sweagentdTwirp.MintUserToServerTokenForReposResponse, error) {
		block("token")
		return &sweagentdTwirp.MintUserToServerTokenForReposResponse{Token: "token"}, nil
	}

	server := &Server{
		obsv:    observability.NewNoopExporters(),
		ghTwirp: ghTwirp,
	}

	done := make(chan *agentComputeSetupData, 1)
	errs := make(chan error, 1)
	go func() {
		setup, err := server.fetchAgentComputeSetupData(context.Background(), &jobs_pb.CreateAgentComputeRequest{
			RepositoryId:      42,
			RepositoryOwnerId: 7,
			ActorId:           99,
			AgentId:           3,
			BranchName:        "main",
		})
		if err != nil {
			errs <- err
			return
		}
		done <- setup
	}()

	seen := map[string]bool{}
	for range 3 {
		select {
		case name := <-started:
			seen[name] = true
		case <-time.After(time.Second):
			t.Fatal("timed out waiting for concurrent setup requests")
		}
	}
	close(release)

	var setup *agentComputeSetupData
	select {
	case err := <-errs:
		require.NoError(t, err)
	case setup = <-done:
	}

	assert.Equal(t, map[string]bool{"repo": true, "config": true, "token": true}, seen)
	require.NotNil(t, setup)
	assert.Equal(t, "owner/repo", setup.repoNWO)
	assert.Equal(t, "token", setup.token)
	assert.True(t, setup.repoConfig.GetIsFirewallEnabled())
	assert.True(t, setup.repoConfig.GetShouldFirewallUseDefaultRules())
	assert.Equal(t, []string{"api.example.com"}, setup.repoConfig.GetFirewallAllowedRules())
}

func TestCreateAgentCompute_DisallowFlagBlocksRepo(t *testing.T) {
	const repoID = uint64(42)

	req := &jobs_pb.CreateAgentComputeRequest{
		RepositoryId:      repoID,
		RepositoryOwnerId: 7,
		ActorId:           99,
		AgentId:           3,
		BranchName:        "main",
	}

	t.Run("blocks the request when the disallow flag is set on the repo", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentDisallow: true,
		})

		server := &Server{
			obsv:     observability.NewNoopExporters(),
			ffClient: ffClient,
		}

		_, err := server.CreateAgentCompute(context.Background(), req)
		require.Error(t, err)
		var twerr twirp.Error
		require.True(t, errors.As(err, &twerr))
		assert.Equal(t, twirp.PermissionDenied, twerr.Code())
		assert.Contains(t, twerr.Msg(), "not allowed")
	})

	t.Run("allows the request when the disallow flag is not set", func(t *testing.T) {
		gh := githubtwirp.NewNoopClient()
		gh.NoopRepositoriesAPI.MockFindRepositories = func(_ context.Context, r *repositoriesTwirp.FindRepositoriesRequest) (*repositoriesTwirp.FindRepositoriesResponse, error) {
			return &repositoriesTwirp.FindRepositoriesResponse{
				Repositories: []*repositoriesTwirp.RepositoryListItem{{
					Id:         r.GetIds()[0],
					OwnerLogin: "owner",
					Name:       "repo",
				}},
			}, nil
		}

		server := &Server{
			obsv:           observability.NewNoopExporters(),
			ffClient:       featureflags.NewNoopClient(nil),
			ghTwirp:        gh,
			sandboxService: fakeSandbox{},
		}

		_, err := server.CreateAgentCompute(context.Background(), req)
		require.NoError(t, err)
	})
}

func TestFetchAgentComputeSetupDataSkipsRepoCallsWhenRepositoryIDIsZero(t *testing.T) {
	ghTwirp := githubtwirp.NewNoopClient()
	ghTwirp.NoopRepositoriesAPI.MockFindRepositories = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesRequest) (*repositoriesTwirp.FindRepositoriesResponse, error) {
		t.Fatal("FindRepositories should not be called when repository_id is 0")
		return nil, nil
	}
	ghTwirp.NoopSweagentdAPI.MockConfigurationForRepository = func(ctx context.Context, req *sweagentdTwirp.ConfigurationForRepositoryRequest) (*sweagentdTwirp.ConfigurationForRepositoryResponse, error) {
		t.Fatal("ConfigurationForRepository should not be called when repository_id is 0")
		return nil, nil
	}
	ghTwirp.NoopSweagentdAPI.MockGetRepositoryInstallation = func(ctx context.Context, req *sweagentdTwirp.GetRepositoryInstallationRequest) (*sweagentdTwirp.GetRepositoryInstallationResponse, error) {
		t.Fatal("GetRepositoryInstallation should not be called when repository_id is 0")
		return nil, nil
	}
	var capturedMintReq *sweagentdTwirp.MintUserToServerTokenForReposRequest
	ghTwirp.NoopSweagentdAPI.MockMintUserToServerTokenForRepos = func(ctx context.Context, req *sweagentdTwirp.MintUserToServerTokenForReposRequest) (*sweagentdTwirp.MintUserToServerTokenForReposResponse, error) {
		capturedMintReq = req
		return &sweagentdTwirp.MintUserToServerTokenForReposResponse{Token: "scoped-token"}, nil
	}

	server := &Server{
		obsv:    observability.NewNoopExporters(),
		ghTwirp: ghTwirp,
	}

	setup, err := server.fetchAgentComputeSetupData(context.Background(), &jobs_pb.CreateAgentComputeRequest{
		ActorId: 99,
		AgentId: 3,
		ScopeId: 1234,
	})
	require.NoError(t, err)
	require.NotNil(t, setup)
	assert.Equal(t, "", setup.repoNWO)
	assert.Nil(t, setup.repoConfig)
	assert.Equal(t, "scoped-token", setup.token)
	require.NotNil(t, capturedMintReq)
	assert.Equal(t, uint64(1234), capturedMintReq.ScopeId)
	assert.Empty(t, capturedMintReq.Repositories)
	assert.NotEmpty(t, capturedMintReq.Permissions)
}

func TestCreateAgentComputeResolvesOwnerTypeFromScopeWhenNoRepository(t *testing.T) {
	cases := []struct {
		name              string
		userType          string
		wantOwnerType     string
		wantResolveCalled bool
	}{
		{name: "organization scope", userType: "Organization", wantOwnerType: string(sweagentd.OwnerTypeOrganization), wantResolveCalled: true},
		{name: "user scope", userType: "User", wantOwnerType: string(sweagentd.OwnerTypeUser), wantResolveCalled: true},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			const scopeID uint64 = 4242

			ghTwirp := githubtwirp.NewNoopClient()
			ghTwirp.NoopSweagentdAPI.MockMintUserToServerTokenForRepos = func(ctx context.Context, req *sweagentdTwirp.MintUserToServerTokenForReposRequest) (*sweagentdTwirp.MintUserToServerTokenForReposResponse, error) {
				return &sweagentdTwirp.MintUserToServerTokenForReposResponse{Token: "scoped-token"}, nil
			}

			var capturedScopeID uint64
			ghf := &github.NoopClientFactory{
				MockGetUserByID: func(ctx context.Context, id uint64) (*gg.User, error) {
					capturedScopeID = id
					return &gg.User{Type: gg.Ptr(tc.userType)}, nil
				},
			}

			var capturedParams *sandbox.CreateSandboxParams
			server := &Server{
				obsv:        observability.NewNoopExporters(),
				ghTwirp:     ghTwirp,
				ghf:         ghf,
				ffClient:    featureflags.NewNoopClient(nil),
				appProvider: agenticapptest.NewTestProviderWithID(t, 3),
				sandboxService: &captureSandbox{
					onCreate: func(p *sandbox.CreateSandboxParams) {
						capturedParams = p
					},
				},
			}

			_, err := server.CreateAgentCompute(context.Background(), &jobs_pb.CreateAgentComputeRequest{
				ActorId: 99,
				AgentId: 3,
				ScopeId: scopeID,
			})
			require.NoError(t, err)
			require.NotNil(t, capturedParams)
			assert.Equal(t, tc.wantOwnerType, capturedParams.BillableOwnerType)
			assert.Equal(t, scopeID, capturedScopeID)
		})
	}
}

type captureSandbox struct {
	fakeSandbox

	onCreate func(*sandbox.CreateSandboxParams)
}

func (c *captureSandbox) CreateSandbox(_ context.Context, p *sandbox.CreateSandboxParams) (*sandbox.CreateSandboxResult, error) {
	if c.onCreate != nil {
		c.onCreate(p)
	}
	return &sandbox.CreateSandboxResult{}, nil
}

func TestDeleteAgentCompute_ValidationErrors(t *testing.T) {
	server := &Server{
		obsv: observability.NewNoopExporters(),
	}

	tests := []struct {
		name    string
		req     *jobs_pb.DeleteAgentComputeRequest
		wantArg string
	}{
		{
			name:    "missing compute_id",
			req:     &jobs_pb.DeleteAgentComputeRequest{ActorId: 1},
			wantArg: "compute_id",
		},
		{
			name:    "missing actor_id",
			req:     &jobs_pb.DeleteAgentComputeRequest{ComputeId: "sb-123"},
			wantArg: "actor_id",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := server.DeleteAgentCompute(context.Background(), tt.req)
			require.Error(t, err)
			var twerr twirp.Error
			require.True(t, errors.As(err, &twerr))
			assert.Equal(t, twirp.InvalidArgument, twerr.Code())
			assert.Contains(t, twerr.Msg(), tt.wantArg)
		})
	}
}

func TestStopAgentCompute_MissingComputeID(t *testing.T) {
	server := &Server{
		obsv: observability.NewNoopExporters(),
	}

	_, err := server.StopAgentCompute(context.Background(), &jobs_pb.StopAgentComputeRequest{
		ActorId: 1,
	})
	require.Error(t, err)
	var twerr twirp.Error
	require.True(t, errors.As(err, &twerr))
	assert.Equal(t, twirp.InvalidArgument, twerr.Code())
	assert.Contains(t, twerr.Msg(), "compute_id")
}

func TestStopAgentCompute_ValidationErrors(t *testing.T) {
	server := &Server{
		obsv: observability.NewNoopExporters(),
	}

	tests := []struct {
		name    string
		req     *jobs_pb.StopAgentComputeRequest
		wantArg string
	}{
		{
			name:    "missing actor_id",
			req:     &jobs_pb.StopAgentComputeRequest{ComputeId: "sb-1"},
			wantArg: "actor_id",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := server.StopAgentCompute(context.Background(), tt.req)
			require.Error(t, err)
			var twerr twirp.Error
			require.True(t, errors.As(err, &twerr))
			assert.Equal(t, twirp.InvalidArgument, twerr.Code())
			assert.Contains(t, twerr.Msg(), tt.wantArg)
		})
	}
}

func TestStopAgentCompute_NegativeDelay(t *testing.T) {
	server := &Server{
		obsv: observability.NewNoopExporters(),
	}

	_, err := server.StopAgentCompute(context.Background(), &jobs_pb.StopAgentComputeRequest{
		ComputeId: "compute-1",
		ActorId:   1,
		Delay:     durationpb.New(-1 * time.Second),
	})
	require.Error(t, err)
	var twerr twirp.Error
	require.True(t, errors.As(err, &twerr))
	assert.Equal(t, twirp.InvalidArgument, twerr.Code())
	assert.Contains(t, twerr.Msg(), "delay")
}

func TestStopAgentCompute_DelayZero_StopsSynchronouslyAndInvalidatesGeneration(t *testing.T) {
	guard := stopguard.New(cache.NewMemoryCacheStore(), 0)
	gen1, err := guard.Record("compute-1")
	require.NoError(t, err)
	require.True(t, guard.IsCurrent("compute-1", gen1))

	sandbox := &trackingSandbox{}
	server := &Server{
		obsv:           observability.NewNoopExporters(),
		sandboxService: sandbox,
		stopGuard:      guard,
	}

	_, err = server.StopAgentCompute(context.Background(), &jobs_pb.StopAgentComputeRequest{
		ComputeId: "compute-1",
		ActorId:   123,
		Delay:     durationpb.New(0),
	})
	require.NoError(t, err)
	assert.Equal(t, 1, sandbox.stopCalls)
	assert.Equal(t, "compute-1", sandbox.lastComputeID)
	assert.Equal(t, uint64(123), sandbox.lastActorID)
	assert.False(t, guard.IsCurrent("compute-1", gen1),
		"expected synchronous stop to invalidate prior delayed stop generation")
}

func TestStopAgentCompute_DefaultDelay_SchedulesJobAndRecordsGeneration(t *testing.T) {
	guard := stopguard.New(cache.NewMemoryCacheStore(), 0)
	sandbox := &trackingSandbox{}
	aqueductClient := &mockAqueductClient{}
	server := &Server{
		obsv:           observability.NewNoopExporters(),
		sandboxService: sandbox,
		aqueductClient: aqueductClient,
		stopGuard:      guard,
	}

	start := time.Now()
	_, err := server.StopAgentCompute(context.Background(), &jobs_pb.StopAgentComputeRequest{
		ComputeId: "compute-1",
		ActorId:   123,
	})
	require.NoError(t, err)

	assert.Equal(t, 0, sandbox.stopCalls, "expected delayed stop to avoid synchronous stop")
	require.Len(t, aqueductClient.scheduledJobs, 1)
	require.Len(t, aqueductClient.scheduledAt, 1)

	job, ok := aqueductClient.scheduledJobs[0].(*aqueductJobs.StopAgentComputeJob)
	require.True(t, ok)
	assert.Equal(t, "compute-1", job.ComputeId)
	assert.Equal(t, int64(123), job.ActorId)
	assert.Greater(t, job.Generation, int64(0))
	assert.True(t, guard.IsCurrent("compute-1", job.Generation))

	minDeliverAt := start.Add(DefaultStopAgentComputeDelay).Add(-1 * time.Second)
	maxDeliverAt := start.Add(DefaultStopAgentComputeDelay).Add(1 * time.Second)
	assert.False(t, aqueductClient.scheduledAt[0].Before(minDeliverAt))
	assert.False(t, aqueductClient.scheduledAt[0].After(maxDeliverAt))
}

func TestResumeAgentCompute_MissingComputeID(t *testing.T) {
	server := &Server{
		obsv: observability.NewNoopExporters(),
	}

	_, err := server.ResumeAgentCompute(context.Background(), &jobs_pb.ResumeAgentComputeRequest{
		ActorId: 1,
	})
	require.Error(t, err)
	var twerr twirp.Error
	require.True(t, errors.As(err, &twerr))
	assert.Equal(t, twirp.InvalidArgument, twerr.Code())
	assert.Contains(t, twerr.Msg(), "compute_id")
}

func TestResumeAgentCompute_ValidationErrors(t *testing.T) {
	server := &Server{
		obsv: observability.NewNoopExporters(),
	}

	tests := []struct {
		name    string
		req     *jobs_pb.ResumeAgentComputeRequest
		wantArg string
	}{
		{
			name:    "missing actor_id",
			req:     &jobs_pb.ResumeAgentComputeRequest{ComputeId: "sb-1"},
			wantArg: "actor_id",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := server.ResumeAgentCompute(context.Background(), tt.req)
			require.Error(t, err)
			var twerr twirp.Error
			require.True(t, errors.As(err, &twerr))
			assert.Equal(t, twirp.InvalidArgument, twerr.Code())
			assert.Contains(t, twerr.Msg(), tt.wantArg)
		})
	}
}

func TestResumeAgentCompute_InvalidatesStopGeneration(t *testing.T) {
	guard := stopguard.New(cache.NewMemoryCacheStore(), 0)
	gen1, err := guard.Record("compute-1")
	require.NoError(t, err)
	require.True(t, guard.IsCurrent("compute-1", gen1))

	// Use a sandbox stub whose labels are missing so the handler fails
	// fast on the full-resume path; we are only exercising the
	// stopguard-bump path of the handler.
	sandboxSvc := &trackingSandbox{
		stateValue: "suspended",
		getInfoErr: sandbox.ErrSandboxLabelsMissing,
	}
	server := &Server{
		obsv:           observability.NewNoopExporters(),
		sandboxService: sandboxSvc,
		stopGuard:      guard,
	}

	_, err = server.ResumeAgentCompute(context.Background(), &jobs_pb.ResumeAgentComputeRequest{
		ComputeId: "compute-1",
		ActorId:   1,
	})
	require.Error(t, err)

	assert.False(t, guard.IsCurrent("compute-1", gen1),
		"expected resume to bump generation so prior pending stop is invalidated")
}

func TestResumeAgentCompute_HappyPath(t *testing.T) {
	guard := stopguard.New(cache.NewMemoryCacheStore(), 0)

	const repoID, agentID, actorID = int64(42), int64(7), uint64(99)
	const computeID = "sb-resume-1"

	ghTwirp := githubtwirp.NewNoopClient()
	ghTwirp.NoopRepositoriesAPI.MockFindRepositories = func(_ context.Context, req *repositoriesTwirp.FindRepositoriesRequest) (*repositoriesTwirp.FindRepositoriesResponse, error) {
		require.Equal(t, []int64{repoID}, req.GetIds())
		return &repositoriesTwirp.FindRepositoriesResponse{
			Repositories: []*repositoriesTwirp.RepositoryListItem{{
				Id:         repoID,
				OwnerLogin: "owner",
				Name:       "repo",
			}},
		}, nil
	}
	mintCalls := 0
	ghTwirp.NoopSweagentdAPI.MockMintUserToServerTokenForRepos = func(_ context.Context, req *sweagentdTwirp.MintUserToServerTokenForReposRequest) (*sweagentdTwirp.MintUserToServerTokenForReposResponse, error) {
		mintCalls++
		require.Equal(t, actorID, req.UserId)
		require.Equal(t, agentID, req.AgentId)
		require.Len(t, req.Repositories, 1)
		require.Equal(t, uint64(repoID), req.Repositories[0].RepositoryId)
		return &sweagentdTwirp.MintUserToServerTokenForReposResponse{Token: "fresh-token-abc"}, nil
	}

	sandboxSvc := &trackingSandbox{
		stateValue:  "suspended",
		getInfoResp: &sandbox.Info{RepositoryID: repoID, AgentID: agentID},
	}
	server := &Server{
		obsv:           observability.NewNoopExporters(),
		ghTwirp:        ghTwirp,
		sandboxService: sandboxSvc,
		stopGuard:      guard,
	}

	_, err := server.ResumeAgentCompute(context.Background(), &jobs_pb.ResumeAgentComputeRequest{
		ComputeId: computeID,
		ActorId:   actorID,
	})
	require.NoError(t, err)

	assert.Equal(t, 1, sandboxSvc.resumeCalls, "ResumeSandbox should be called once")
	assert.Equal(t, 1, mintCalls, "token mint should be called once")
	assert.Equal(t, 1, sandboxSvc.resumeCLICalls, "ResumeCopilotCLI should be called once")
	assert.Equal(t, computeID, sandboxSvc.resumeCLILastID)
	assert.Equal(t, actorID, sandboxSvc.resumeCLILastActor)
	assert.Equal(t, "owner/repo", sandboxSvc.resumeCLILastRepo)
	assert.Equal(t, map[string]string{
		"GITHUB_COPILOT_API_TOKEN": "fresh-token-abc",
		"GITHUB_COPILOT_GIT_TOKEN": "fresh-token-abc",
		"GITHUB_TOKEN":             "fresh-token-abc",
		"REMOTE_JSON_RPC":          "true",
	}, sandboxSvc.resumeCLILastEnv)
	assert.Equal(t, 0, sandboxSvc.stopCalls, "no stop on happy path")
}

func TestResumeAgentCompute_LabelsMissing_NoResumeNoMint(t *testing.T) {
	guard := stopguard.New(cache.NewMemoryCacheStore(), 0)
	ghTwirp := githubtwirp.NewNoopClient()
	mintCalled := false
	ghTwirp.NoopSweagentdAPI.MockMintUserToServerTokenForRepos = func(context.Context, *sweagentdTwirp.MintUserToServerTokenForReposRequest) (*sweagentdTwirp.MintUserToServerTokenForReposResponse, error) {
		mintCalled = true
		return &sweagentdTwirp.MintUserToServerTokenForReposResponse{Token: "x"}, nil
	}

	sandboxSvc := &trackingSandbox{
		stateValue: "suspended",
		getInfoErr: sandbox.ErrSandboxLabelsMissing,
	}
	server := &Server{
		obsv:           observability.NewNoopExporters(),
		ghTwirp:        ghTwirp,
		sandboxService: sandboxSvc,
		stopGuard:      guard,
	}

	_, err := server.ResumeAgentCompute(context.Background(), &jobs_pb.ResumeAgentComputeRequest{
		ComputeId: "sb-1",
		ActorId:   1,
	})
	require.Error(t, err)
	var twerr twirp.Error
	require.True(t, errors.As(err, &twerr))
	assert.Equal(t, twirp.Internal, twerr.Code())

	assert.Equal(t, 0, sandboxSvc.resumeCalls, "no resume when labels missing")
	assert.Equal(t, 0, sandboxSvc.resumeCLICalls, "no relaunch when labels missing")
	assert.Equal(t, 0, sandboxSvc.stopCalls, "no stop when we never resumed")
	assert.False(t, mintCalled, "no token mint when labels missing")
}

func TestResumeAgentCompute_ResumeFailure_NoMintNoStop(t *testing.T) {
	guard := stopguard.New(cache.NewMemoryCacheStore(), 0)
	ghTwirp := githubtwirp.NewNoopClient()
	ghTwirp.NoopRepositoriesAPI.MockFindRepositories = func(_ context.Context, req *repositoriesTwirp.FindRepositoriesRequest) (*repositoriesTwirp.FindRepositoriesResponse, error) {
		return &repositoriesTwirp.FindRepositoriesResponse{
			Repositories: []*repositoriesTwirp.RepositoryListItem{{
				Id: req.GetIds()[0], OwnerLogin: "o", Name: "r",
			}},
		}, nil
	}
	mintCalled := false
	ghTwirp.NoopSweagentdAPI.MockMintUserToServerTokenForRepos = func(context.Context, *sweagentdTwirp.MintUserToServerTokenForReposRequest) (*sweagentdTwirp.MintUserToServerTokenForReposResponse, error) {
		mintCalled = true
		return &sweagentdTwirp.MintUserToServerTokenForReposResponse{Token: "x"}, nil
	}

	sandboxSvc := &trackingSandbox{
		stateValue:  "suspended",
		getInfoResp: &sandbox.Info{RepositoryID: 1, AgentID: 1},
		resumeErr:   goerrors.New("boom"),
	}
	server := &Server{
		obsv:           observability.NewNoopExporters(),
		ghTwirp:        ghTwirp,
		sandboxService: sandboxSvc,
		stopGuard:      guard,
	}

	_, err := server.ResumeAgentCompute(context.Background(), &jobs_pb.ResumeAgentComputeRequest{
		ComputeId: "sb-1",
		ActorId:   1,
	})
	require.Error(t, err)
	assert.Equal(t, 1, sandboxSvc.resumeCalls)
	assert.Equal(t, 0, sandboxSvc.resumeCLICalls)
	assert.Equal(t, 0, sandboxSvc.stopCalls, "no stop when resume itself failed")
	assert.False(t, mintCalled, "no token mint when resume failed")
}

func TestResumeAgentCompute_TokenMintFailure_StopsSandbox(t *testing.T) {
	guard := stopguard.New(cache.NewMemoryCacheStore(), 0)
	ghTwirp := githubtwirp.NewNoopClient()
	ghTwirp.NoopRepositoriesAPI.MockFindRepositories = func(_ context.Context, req *repositoriesTwirp.FindRepositoriesRequest) (*repositoriesTwirp.FindRepositoriesResponse, error) {
		return &repositoriesTwirp.FindRepositoriesResponse{
			Repositories: []*repositoriesTwirp.RepositoryListItem{{
				Id: req.GetIds()[0], OwnerLogin: "o", Name: "r",
			}},
		}, nil
	}
	ghTwirp.NoopSweagentdAPI.MockMintUserToServerTokenForRepos = func(context.Context, *sweagentdTwirp.MintUserToServerTokenForReposRequest) (*sweagentdTwirp.MintUserToServerTokenForReposResponse, error) {
		return nil, goerrors.New("mint boom")
	}

	sandboxSvc := &trackingSandbox{
		stateValue:  "suspended",
		getInfoResp: &sandbox.Info{RepositoryID: 1, AgentID: 1},
	}
	server := &Server{
		obsv:           observability.NewNoopExporters(),
		ghTwirp:        ghTwirp,
		sandboxService: sandboxSvc,
		stopGuard:      guard,
	}

	_, err := server.ResumeAgentCompute(context.Background(), &jobs_pb.ResumeAgentComputeRequest{
		ComputeId: "sb-1",
		ActorId:   1,
	})
	require.Error(t, err)
	assert.Equal(t, 1, sandboxSvc.resumeCalls)
	assert.Equal(t, 0, sandboxSvc.resumeCLICalls, "should not relaunch CLI after token mint failure")
	assert.Equal(t, 1, sandboxSvc.stopCalls, "best-effort stop after token mint failure")
}

func TestResumeAgentCompute_ResumeCopilotCLIFailure_StopsSandbox(t *testing.T) {
	guard := stopguard.New(cache.NewMemoryCacheStore(), 0)
	ghTwirp := githubtwirp.NewNoopClient()
	ghTwirp.NoopRepositoriesAPI.MockFindRepositories = func(_ context.Context, req *repositoriesTwirp.FindRepositoriesRequest) (*repositoriesTwirp.FindRepositoriesResponse, error) {
		return &repositoriesTwirp.FindRepositoriesResponse{
			Repositories: []*repositoriesTwirp.RepositoryListItem{{
				Id: req.GetIds()[0], OwnerLogin: "o", Name: "r",
			}},
		}, nil
	}
	ghTwirp.NoopSweagentdAPI.MockMintUserToServerTokenForRepos = func(context.Context, *sweagentdTwirp.MintUserToServerTokenForReposRequest) (*sweagentdTwirp.MintUserToServerTokenForReposResponse, error) {
		return &sweagentdTwirp.MintUserToServerTokenForReposResponse{Token: "fresh"}, nil
	}

	sandboxSvc := &trackingSandbox{
		stateValue:   "suspended",
		getInfoResp:  &sandbox.Info{RepositoryID: 1, AgentID: 1},
		resumeCLIErr: goerrors.New("relaunch boom"),
	}
	server := &Server{
		obsv:           observability.NewNoopExporters(),
		ghTwirp:        ghTwirp,
		sandboxService: sandboxSvc,
		stopGuard:      guard,
	}

	_, err := server.ResumeAgentCompute(context.Background(), &jobs_pb.ResumeAgentComputeRequest{
		ComputeId: "sb-1",
		ActorId:   1,
	})
	require.Error(t, err)
	assert.Equal(t, 1, sandboxSvc.resumeCalls)
	assert.Equal(t, 1, sandboxSvc.resumeCLICalls)
	assert.Equal(t, 1, sandboxSvc.stopCalls, "best-effort stop after relaunch failure")
}

func TestResumeAgentCompute_NoOpWhenSandboxRunning(t *testing.T) {
	guard := stopguard.New(cache.NewMemoryCacheStore(), 0)
	// Schedule a delayed stop so we can also verify Resume invalidates it
	// on the no-op path.
	gen1, err := guard.Record("compute-running")
	require.NoError(t, err)
	require.True(t, guard.IsCurrent("compute-running", gen1))

	ghTwirp := githubtwirp.NewNoopClient()
	ghTwirp.NoopRepositoriesAPI.MockFindRepositories = func(context.Context, *repositoriesTwirp.FindRepositoriesRequest) (*repositoriesTwirp.FindRepositoriesResponse, error) {
		t.Fatal("FindRepositories should not be called on the no-op path")
		return nil, nil
	}
	ghTwirp.NoopSweagentdAPI.MockMintUserToServerTokenForRepos = func(context.Context, *sweagentdTwirp.MintUserToServerTokenForReposRequest) (*sweagentdTwirp.MintUserToServerTokenForReposResponse, error) {
		t.Fatal("token mint should not be called on the no-op path")
		return nil, nil
	}

	sandboxSvc := &trackingSandbox{
		stateValue: "running",
	}
	server := &Server{
		obsv:           observability.NewNoopExporters(),
		ghTwirp:        ghTwirp,
		sandboxService: sandboxSvc,
		stopGuard:      guard,
	}

	_, err = server.ResumeAgentCompute(context.Background(), &jobs_pb.ResumeAgentComputeRequest{
		ComputeId: "compute-running",
		ActorId:   42,
	})
	require.NoError(t, err)

	assert.Equal(t, 1, sandboxSvc.stateCalls, "GetSandboxState should be called once")
	assert.Equal(t, 0, sandboxSvc.getInfoCalls, "no-op path must not fetch labels at all")
	assert.Equal(t, 0, sandboxSvc.resumeCalls, "ResumeSandbox must not run when VM is already running")
	assert.Equal(t, 0, sandboxSvc.resumeCLICalls, "ResumeCopilotCLI must not run when VM is already running")
	assert.Equal(t, 0, sandboxSvc.stopCalls, "no best-effort stop on the no-op path")
	assert.False(t, guard.IsCurrent("compute-running", gen1),
		"the no-op path should still bump the stopGuard generation to invalidate pending stops")
}

func TestResumeAgentCompute_FullResumeWhenSuspended(t *testing.T) {
	guard := stopguard.New(cache.NewMemoryCacheStore(), 0)

	const repoID, agentID, actorID = int64(42), int64(7), uint64(99)
	const computeID = "sb-suspended-1"

	ghTwirp := githubtwirp.NewNoopClient()
	ghTwirp.NoopRepositoriesAPI.MockFindRepositories = func(_ context.Context, req *repositoriesTwirp.FindRepositoriesRequest) (*repositoriesTwirp.FindRepositoriesResponse, error) {
		return &repositoriesTwirp.FindRepositoriesResponse{
			Repositories: []*repositoriesTwirp.RepositoryListItem{{
				Id: req.GetIds()[0], OwnerLogin: "owner", Name: "repo",
			}},
		}, nil
	}
	mintCalls := 0
	ghTwirp.NoopSweagentdAPI.MockMintUserToServerTokenForRepos = func(_ context.Context, _ *sweagentdTwirp.MintUserToServerTokenForReposRequest) (*sweagentdTwirp.MintUserToServerTokenForReposResponse, error) {
		mintCalls++
		return &sweagentdTwirp.MintUserToServerTokenForReposResponse{Token: "fresh-token"}, nil
	}

	sandboxSvc := &trackingSandbox{
		stateValue:  "suspended",
		getInfoResp: &sandbox.Info{RepositoryID: repoID, AgentID: agentID},
	}
	server := &Server{
		obsv:           observability.NewNoopExporters(),
		ghTwirp:        ghTwirp,
		sandboxService: sandboxSvc,
		stopGuard:      guard,
	}

	_, err := server.ResumeAgentCompute(context.Background(), &jobs_pb.ResumeAgentComputeRequest{
		ComputeId: computeID,
		ActorId:   actorID,
	})
	require.NoError(t, err)
	assert.Equal(t, 1, sandboxSvc.resumeCalls, "full path runs ResumeSandbox")
	assert.Equal(t, 1, mintCalls, "full path mints a fresh token")
	assert.Equal(t, 1, sandboxSvc.resumeCLICalls, "full path relaunches Copilot CLI")
	assert.Equal(t, 0, sandboxSvc.stopCalls, "no best-effort stop on the happy full-resume path")
}

func TestResumeAgentCompute_StateQueryFailure_FailsClosed(t *testing.T) {
	guard := stopguard.New(cache.NewMemoryCacheStore(), 0)

	ghTwirp := githubtwirp.NewNoopClient()
	ghTwirp.NoopRepositoriesAPI.MockFindRepositories = func(context.Context, *repositoriesTwirp.FindRepositoriesRequest) (*repositoriesTwirp.FindRepositoriesResponse, error) {
		t.Fatal("FindRepositories should not be called when state query fails")
		return nil, nil
	}
	ghTwirp.NoopSweagentdAPI.MockMintUserToServerTokenForRepos = func(context.Context, *sweagentdTwirp.MintUserToServerTokenForReposRequest) (*sweagentdTwirp.MintUserToServerTokenForReposResponse, error) {
		t.Fatal("token mint should not be called when state query fails")
		return nil, nil
	}

	sandboxSvc := &trackingSandbox{
		stateErr: goerrors.New("launch unavailable"),
	}
	server := &Server{
		obsv:           observability.NewNoopExporters(),
		ghTwirp:        ghTwirp,
		sandboxService: sandboxSvc,
		stopGuard:      guard,
	}

	_, err := server.ResumeAgentCompute(context.Background(), &jobs_pb.ResumeAgentComputeRequest{
		ComputeId: "sb-1",
		ActorId:   1,
	})
	require.Error(t, err)
	var twerr twirp.Error
	require.True(t, errors.As(err, &twerr))
	assert.Equal(t, twirp.Internal, twerr.Code())

	// Most importantly: none of the destructive side effects ran. A
	// transient state-query failure must NOT take down a possibly-running
	// in-VM tmux session.
	assert.Equal(t, 0, sandboxSvc.resumeCalls, "no ResumeSandbox when state query failed")
	assert.Equal(t, 0, sandboxSvc.resumeCLICalls, "no ResumeCopilotCLI when state query failed")
	assert.Equal(t, 0, sandboxSvc.stopCalls, "no StopSandbox when state query failed")
}

func TestDeleteAgentCompute_InvalidatesStopGeneration(t *testing.T) {
	guard := stopguard.New(cache.NewMemoryCacheStore(), 0)
	gen1, err := guard.Record("compute-1")
	require.NoError(t, err)
	require.True(t, guard.IsCurrent("compute-1", gen1))

	server := &Server{
		obsv:           observability.NewNoopExporters(),
		sandboxService: fakeSandbox{},
		stopGuard:      guard,
	}

	_, err = server.DeleteAgentCompute(context.Background(), &jobs_pb.DeleteAgentComputeRequest{
		ComputeId: "compute-1",
		ActorId:   1,
	})
	require.NoError(t, err)

	assert.False(t, guard.IsCurrent("compute-1", gen1),
		"expected delete to bump generation so prior pending stop is invalidated")
}
