package jobs

import (
	"context"
	"testing"
	"time"

	"github.com/github/turboscan/ts"
	ma "github.com/github/turboscan/ts/managedanalyses"
	maservice "github.com/github/turboscan/ts/managedanalyses/service"
	"github.com/github/turboscan/ts/twirp/clients/actions"
	"github.com/github/turboscan/ts/twirp/clients/ghgh"

	"github.com/stretchr/testify/require"
)

func TestRunCodeqlOnPullRequest_perform(t *testing.T) {
	ctx := context.Background()
	r := RunCodeqlOnPullRequest{
		RepoID:     ts.RepositoryEID(123),
		Sha:        "abcdef",
		ActorGRID:  "abc",
		ActorLogin: "monalisa",
		PRNumber:   1,
	}
	config := (&ts.CodeqlConfig{RepositoryID: r.RepoID}).MakeCurrent()
	repo := &ts.CodeqlRepo{
		RepositoryID:  r.RepoID,
		CurrentConfig: config,
	}

	mock := &MockSuccess{
		repoOut: repo,
	}
	ma := &maservice.ManagedAnalyses{
		GitHubTwirpApiClient: mock,
		DataService:          mock,
		LaunchApiClient:      mock,
	}

	// Check that we are using the special PR head ref refs/pull/N/head
	err := r.perform(ctx, ma)
	require.NoError(t, err)
	require.Equal(t, ts.Ref("refs/pull/1/head"), mock.actualRunRef)
}

func TestNilLaunchApiClient(t *testing.T) {
	ctx := context.Background()
	r := RunCodeqlOnPullRequest{
		RepoID:     ts.RepositoryEID(123),
		Sha:        "abcdef",
		ActorGRID:  "abc",
		ActorLogin: "monalisa",
		PRNumber:   1,
	}
	config := (&ts.CodeqlConfig{RepositoryID: r.RepoID}).MakeCurrent()
	repo := &ts.CodeqlRepo{
		RepositoryID:  r.RepoID,
		CurrentConfig: config,
	}

	mock := &MockSuccess{
		repoOut: repo,
	}
	ma := &maservice.ManagedAnalyses{
		GitHubTwirpApiClient: mock,
		DataService:          mock,
		LaunchApiClient:      nil,
	}

	err := r.perform(ctx, ma)
	require.NoError(t, err)
	require.False(t, mock.runWorkflow)
}

type MockSuccess struct {
	ma.CodeqlDB
	ghgh.ManagedAnalysesAPI
	actions.DynamicWorkflowRunner

	repoOut      *ts.CodeqlRepo
	actualRunRef ts.Ref
	runWorkflow  bool
}

func (m *MockSuccess) AreRequiredServicesEnabled(ctx context.Context, repoID ts.RepositoryEID) (bool, *ts.ProximaTenant, ts.CodeqlPacks, error) {
	return true, &ts.ProximaTenant{Slug: "avocado-corp", ID: 123}, ts.CodeqlPacks("myorg/mypack@1.2.3"), nil
}

func (m *MockSuccess) RunDynamicWorkflow(ctx context.Context, run *ts.CodeqlRun) error {
	m.actualRunRef = run.Ref
	m.runWorkflow = true
	return nil
}

func (m *MockSuccess) GetCodeqlRepo(context.Context, ts.RepositoryEID) (*ts.CodeqlRepo, error) {
	return m.repoOut, nil
}

func (m *MockSuccess) PreviousRunExists(ctx context.Context, repoID ts.RepositoryEID, sha ts.Sha, ref ts.Ref) (bool, error) {
	return false, nil
}

func (m *MockSuccess) CreateCodeqlRun(context.Context, *ts.CodeqlRun) error {
	return nil
}

func (m *MockSuccess) GetPendingRunsForRef(ctx context.Context, repoID ts.RepositoryEID, ref ts.Ref, olderThan time.Time) ([]ts.CodeqlRun, error) {
	return nil, nil
}
