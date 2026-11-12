package varfetcher

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"sync/atomic"
	"testing"

	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/sweagentd"
	sweagentdv1 "github.com/github/sweagentd/proto/sweagentd/v1"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// mockApp implements sweagentd.AgenticApp for testing.
type mockApp struct{ id int64 }

func (m *mockApp) AppID() int64                        { return m.id }
func (m *mockApp) AppName() string                     { return "test-app" }
func (m *mockApp) BranchPrefix() string                { return "" }
func (m *mockApp) BotID() int64                        { return 0 }
func (m *mockApp) BotLogin() string                    { return "" }
func (m *mockApp) CommitLogin() string                 { return "" }
func (m *mockApp) CommitEmail() string                 { return "" }
func (m *mockApp) MentionableSlug() string             { return "" }
func (m *mockApp) ComputeSlug() string                 { return "" }
func (m *mockApp) EngineSlug() string                  { return "" }
func (m *mockApp) HasSource() bool                     { return false }
func (m *mockApp) SourceURL() string                   { return "" }
func (m *mockApp) AgentSource() *sweagentd.AgentSource { return nil }
func (m *mockApp) IsGlobalApp() bool                   { return false }
func (m *mockApp) IsPartnerApp() bool                  { return false }
func (m *mockApp) IsThirdPartyApp() bool               { return true }
func (m *mockApp) ModelVendors() []string              { return nil }
func (m *mockApp) Metadata() map[string]string         { return nil }
func (m *mockApp) SetupCompute(_ sweagentd.ComputeEnv) {}
func (m *mockApp) WorkflowRunName(_ int) string        { return "" }
func (m *mockApp) IsQuotaExempt() bool                 { return false }
func (m *mockApp) UsesExperiments() bool               { return true }
func (m *mockApp) RevokeToken(_ context.Context, _ sweagentd.GitHubAPI, _ string) error {
	return nil
}

// mockGHClient implements the GetAgentVariableValue method needed by the fetcher.
type mockGHClient struct {
	github.NoopClient

	values map[string]string
	err    error
	calls  atomic.Int64
}

func (m *mockGHClient) GetAgentVariableValue(_ context.Context, _, _, variableName string, _ bool) (string, error) {
	m.calls.Add(1)
	if m.err != nil {
		return "", m.err
	}
	return m.values[variableName], nil
}

func TestNewGitHubVariableFetcher_EmptyNames(t *testing.T) {
	fetcher := NewGitHubVariableFetcher(&github.NoopClientFactory{}, &githubtwirp.NoopClient{})
	result, err := fetcher(context.Background(), &mockApp{id: 1}, 100, nil)
	require.NoError(t, err)
	assert.Nil(t, result)
}

func TestNewGitHubVariableFetcher_FetchesVariables(t *testing.T) {
	ghClient := &mockGHClient{
		values: map[string]string{
			"COPILOT_MCP_AUD":   "https://example.com",
			"COPILOT_MCP_URL":   "https://api.example.com",
			"COPILOT_MCP_SCOPE": "read write",
		},
	}

	cpf := &github.NoopClientFactory{
		MockNewClientFromRepo: func(_ context.Context, _, _ int64) (github.ClientInterface, error) {
			return ghClient, nil
		},
	}

	noopTwirp := &githubtwirp.NoopClient{
		NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
			MockGetRepositoryInstallation: func(_ context.Context, _ *sweagentdv1.GetRepositoryInstallationRequest) (*sweagentdv1.GetRepositoryInstallationResponse, error) {
				return &sweagentdv1.GetRepositoryInstallationResponse{
					OwnerId:    42,
					OwnerLogin: "test-owner",
					RepoName:   "test-repo",
					OwnerType:  sweagentdv1.RepositoryOwnerType_REPOSITORY_OWNER_TYPE_ORGANIZATION,
				}, nil
			},
		},
	}

	fetcher := NewGitHubVariableFetcher(cpf, noopTwirp)
	names := []string{"COPILOT_MCP_AUD", "COPILOT_MCP_URL", "COPILOT_MCP_SCOPE"}
	result, err := fetcher(context.Background(), &mockApp{id: 1}, 100, names)
	require.NoError(t, err)

	assert.Equal(t, "https://example.com", result["COPILOT_MCP_AUD"])
	assert.Equal(t, "https://api.example.com", result["COPILOT_MCP_URL"])
	assert.Equal(t, "read write", result["COPILOT_MCP_SCOPE"])
	assert.Equal(t, int64(3), ghClient.calls.Load())
}

func TestNewGitHubVariableFetcher_GetInstallationInfoError(t *testing.T) {
	noopTwirp := &githubtwirp.NoopClient{
		NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
			MockGetRepositoryInstallation: func(_ context.Context, _ *sweagentdv1.GetRepositoryInstallationRequest) (*sweagentdv1.GetRepositoryInstallationResponse, error) {
				return nil, goerrors.Errorf("twirp error")
			},
		},
	}

	fetcher := NewGitHubVariableFetcher(&github.NoopClientFactory{}, noopTwirp)
	_, err := fetcher(context.Background(), &mockApp{id: 1}, 100, []string{"COPILOT_MCP_X"})
	require.Error(t, err)
	assert.Contains(t, err.Error(), "installation info")
}

func TestNewGitHubVariableFetcher_NewClientFromRepoError(t *testing.T) {
	cpf := &github.NoopClientFactory{
		MockNewClientFromRepo: func(_ context.Context, _, _ int64) (github.ClientInterface, error) {
			return nil, goerrors.Errorf("client error")
		},
	}
	noopTwirp := &githubtwirp.NoopClient{
		NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{},
	}

	fetcher := NewGitHubVariableFetcher(cpf, noopTwirp)
	_, err := fetcher(context.Background(), &mockApp{id: 1}, 100, []string{"COPILOT_MCP_X"})
	require.Error(t, err)
	assert.Contains(t, err.Error(), "GitHub client")
}

func TestNewGitHubVariableFetcher_VariableError(t *testing.T) {
	ghClient := &mockGHClient{
		err: goerrors.Errorf("api error"),
	}

	cpf := &github.NoopClientFactory{
		MockNewClientFromRepo: func(_ context.Context, _, _ int64) (github.ClientInterface, error) {
			return ghClient, nil
		},
	}
	noopTwirp := &githubtwirp.NoopClient{
		NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{},
	}

	fetcher := NewGitHubVariableFetcher(cpf, noopTwirp)
	_, err := fetcher(context.Background(), &mockApp{id: 1}, 100, []string{"COPILOT_MCP_X"})
	require.Error(t, err)
	assert.Contains(t, err.Error(), "fetch variable")
}

func TestNewGitHubVariableFetcher_BoundedConcurrency(t *testing.T) {
	// Create more than 8 variables to verify chunking works.
	ghClient := &mockGHClient{
		values: make(map[string]string),
	}
	var names []string
	for i := range 20 {
		name := fmt.Sprintf("COPILOT_MCP_VAR_%d", i)
		ghClient.values[name] = fmt.Sprintf("val_%d", i)
		names = append(names, name)
	}

	cpf := &github.NoopClientFactory{
		MockNewClientFromRepo: func(_ context.Context, _, _ int64) (github.ClientInterface, error) {
			return ghClient, nil
		},
	}
	noopTwirp := &githubtwirp.NoopClient{
		NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{},
	}

	fetcher := NewGitHubVariableFetcher(cpf, noopTwirp)
	result, err := fetcher(context.Background(), &mockApp{id: 1}, 100, names)
	require.NoError(t, err)
	assert.Len(t, result, 20)
	for i := range 20 {
		assert.Equal(t, fmt.Sprintf("val_%d", i), result[fmt.Sprintf("COPILOT_MCP_VAR_%d", i)])
	}
	assert.Equal(t, int64(20), ghClient.calls.Load())
}

func TestNewEnvVariableFetcher_MissingFile(t *testing.T) {
	// Run in a temp dir where .env.mcp-dev does not exist.
	dir := t.TempDir()
	t.Chdir(dir)

	fetcher := NewEnvVariableFetcher()
	result, err := fetcher(context.Background(), nil, 0, []string{"COPILOT_MCP_X"})
	require.NoError(t, err)
	assert.Empty(t, result)
}

func TestNewEnvVariableFetcher_ReadsFile(t *testing.T) {
	dir := t.TempDir()
	envFile := filepath.Join(dir, mcpDevEnvFile)
	require.NoError(t, os.WriteFile(envFile, []byte("COPILOT_MCP_AUD=https://example.com\nCOPILOT_MCP_SCOPE=read\nOTHER_VAR=ignored\n"), 0o644))

	t.Chdir(dir)

	fetcher := NewEnvVariableFetcher()
	result, err := fetcher(context.Background(), nil, 0, []string{"COPILOT_MCP_AUD", "COPILOT_MCP_SCOPE", "OTHER_VAR"})
	require.NoError(t, err)

	assert.Equal(t, "https://example.com", result["COPILOT_MCP_AUD"])
	assert.Equal(t, "read", result["COPILOT_MCP_SCOPE"])
	// OTHER_VAR is in the file but doesn't have COPILOT_MCP_ prefix, so it's filtered out.
	_, hasOther := result["OTHER_VAR"]
	assert.False(t, hasOther)
}

func TestNewEnvVariableFetcher_OnlyRequestedNames(t *testing.T) {
	dir := t.TempDir()
	envFile := filepath.Join(dir, mcpDevEnvFile)
	require.NoError(t, os.WriteFile(envFile, []byte("COPILOT_MCP_A=val_a\nCOPILOT_MCP_B=val_b\n"), 0o644))

	t.Chdir(dir)

	fetcher := NewEnvVariableFetcher()
	// Only request A, not B.
	result, err := fetcher(context.Background(), nil, 0, []string{"COPILOT_MCP_A"})
	require.NoError(t, err)

	assert.Equal(t, "val_a", result["COPILOT_MCP_A"])
	_, hasB := result["COPILOT_MCP_B"]
	assert.False(t, hasB)
}

func TestNewEnvVariableFetcher_UnknownVariable(t *testing.T) {
	dir := t.TempDir()
	envFile := filepath.Join(dir, mcpDevEnvFile)
	require.NoError(t, os.WriteFile(envFile, []byte("COPILOT_MCP_A=val_a\n"), 0o644))

	t.Chdir(dir)

	fetcher := NewEnvVariableFetcher()
	result, err := fetcher(context.Background(), nil, 0, []string{"COPILOT_MCP_MISSING"})
	require.NoError(t, err)

	_, hasMissing := result["COPILOT_MCP_MISSING"]
	assert.False(t, hasMissing)
}
