package fakegithub

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"sync"
	"time"

	"github.com/github/blackbird-mw/internal/experiments"
	"github.com/github/blackbird-mw/internal/github"
	ghclient "github.com/github/blackbird-mw/internal/github/client"
	querypb "github.com/github/blackbird-mw/internal/proto/query/v1"
	"github.com/github/blackbird-mw/internal/types"
)

func NewFakeGitHubAPIClient(inner *ghclient.InternalAPIHttpClient) *FakeGitHubAPIHttpClient {
	return &FakeGitHubAPIHttpClient{inner: inner}
}

type FakeGitHubAPIHttpClient struct {
	inner *ghclient.InternalAPIHttpClient
}

func (f *FakeGitHubAPIHttpClient) RepositoryForID(id types.RepoID) *github.Repository {
	url := fmt.Sprintf("%s/%d", f.inner.RepoURL(), id)
	request, err := http.NewRequest("GET", url, nil)
	if err != nil {
		panic(fmt.Sprintf("failed to create request: %v", err))
	}
	var repo *github.Repository
	_, err = f.inner.Do(context.Background(), request, &repo)
	if err != nil {
		panic(fmt.Sprintf("failed to get repository: %v", err))
	}
	return repo
}

func (f *FakeGitHubAPIHttpClient) UpdateRepository(repoID types.RepoID, repo *github.Repository) {
	url := fmt.Sprintf("%s/%d", f.inner.RepoURL(), repoID)
	jsonBody, err := json.Marshal(repo)
	if err != nil {
		panic(fmt.Sprintf("failed to marshal repo: %v", err))
	}
	request, err := http.NewRequest("PUT", url, bytes.NewBuffer(jsonBody))
	if err != nil {
		panic(fmt.Sprintf("failed to create request: %v", err))
	}

	_, err = f.inner.Do(context.Background(), request, nil)
	if err != nil {
		panic(fmt.Sprintf("failed to get repo: %v", err))
	}
}

func (f *FakeGitHubAPIHttpClient) DeleteRepository(repoID types.RepoID) {
	url := fmt.Sprintf("%s/%d", f.inner.RepoURL(), repoID)
	request, err := http.NewRequest("DELETE", url, nil)
	if err != nil {
		panic(fmt.Sprintf("failed to create request: %v", err))
	}
	_, err = f.inner.Do(context.Background(), request, nil)
	if err != nil {
		panic(fmt.Sprintf("failed to get repo: %v", err))
	}
}

func (f *FakeGitHubAPIHttpClient) AddRepository(repo *github.Repository) {
	url := f.inner.RepoURL()
	jsonBody, err := json.Marshal(repo)
	if err != nil {
		panic(fmt.Sprintf("failed to marshal repo: %v", err))
	}
	request, err := http.NewRequest("POST", url, bytes.NewBuffer(jsonBody))
	if err != nil {
		panic(fmt.Sprintf("failed to create request: %v", err))
	}

	_, err = f.inner.Do(context.Background(), request, nil)
	if err != nil {
		panic(fmt.Sprintf("failed to get repo: %v", err))
	}
}

func (f *FakeGitHubAPIHttpClient) Reset() {
	url := fmt.Sprintf("%s/reset", f.inner.BaseUrl())
	request, err := http.NewRequest("GET", url, nil)
	if err != nil {
		panic(fmt.Sprintf("failed to create request: %v", err))
	}
	_, err = f.inner.Do(context.Background(), request, nil)
	if err != nil {
		panic(fmt.Sprintf("failed to reset: %v", err))
	}
}

const (
	AllAccessToken = "all-access-token"

	// NOTE: GitTFSRepoID is force pushed by the incremental ingest test,
	// and cannot be used for other incremental ingest tests afterwards.
	GitTFSRepoID      = types.RepoID(1) // git-tfs/git-tfs.github.com (as created by spokesd's bootstrap scripts)
	GoGitRepoID       = types.RepoID(2) // go-git/go-git-fixtures (as created by script/setup)
	FlushRepoID       = types.RepoID(3) // A dummy repo used only to flush documents
	MojomboGritRepoID = types.RepoID(4) // The base repo for an delta index index test
	GitHubGritRepoID  = types.RepoID(5) // The child repo for a delta index test
	// NOTE: JavaTestRepoID is used for a force push index test, and should be used with care in other tests.
	JavaTestRepoID       = types.RepoID(6)
	EpochBranchingRepoID = types.RepoID(7)
	GoGitOwnerID         = uint32(57653224)
)

var (
	tenantMode = os.Getenv("BLACKBIRD_MW_MODE") == "tenant"

	reposForTest = []github.Repository{
		{
			ID:          GitTFSRepoID,
			NetworkID:   types.NetworkID(GitTFSRepoID),
			OwnerID:     1229346,
			OwnerLogin:  "git-tfs",
			Name:        "git-tfs.github.com",
			Public:      true,
			DiskUsage:   1,
			UpdatedAt:   time.Now(),
			Experiments: experiments.Experiments{experiments.EnableCodeEmbedding: experiments.Enabled},
		},
		{
			ID:          GoGitRepoID,
			NetworkID:   types.NetworkID(GoGitRepoID),
			OwnerID:     GoGitOwnerID,
			OwnerLogin:  "go-git",
			Name:        "go-git-fixtures",
			Public:      true,
			DiskUsage:   1,
			UpdatedAt:   time.Now(),
			Experiments: experiments.Experiments{experiments.EnableCodeEmbedding: experiments.Enabled},
		},
		{
			ID:          FlushRepoID,
			NetworkID:   types.NetworkID(FlushRepoID),
			OwnerID:     GoGitOwnerID,
			OwnerLogin:  "go-git",
			Name:        "go-git-fixtures-2",
			Public:      true,
			DiskUsage:   1,
			UpdatedAt:   time.Now(),
			Experiments: experiments.Experiments{experiments.EnableCodeEmbedding: experiments.Enabled},
		},
		{
			ID:          MojomboGritRepoID,
			NetworkID:   types.NetworkID(MojomboGritRepoID),
			OwnerID:     1,
			OwnerLogin:  "mojombo",
			Name:        "grit",
			Public:      true,
			DiskUsage:   1,
			UpdatedAt:   time.Now(),
			Experiments: experiments.Experiments{experiments.EnableCodeEmbedding: experiments.Enabled},
		},
		{
			ID:          GitHubGritRepoID,
			NetworkID:   4,
			OwnerID:     9919,
			OwnerLogin:  "github",
			Name:        "grit",
			Public:      true,
			DiskUsage:   1,
			UpdatedAt:   time.Now(),
			Experiments: experiments.Experiments{experiments.EnableCodeEmbedding: experiments.Enabled},
		},
		{
			ID:          JavaTestRepoID,
			NetworkID:   types.NetworkID(JavaTestRepoID),
			OwnerID:     941226,
			OwnerLogin:  "rewinfrey",
			Name:        "java-test",
			Public:      true,
			DiskUsage:   1,
			UpdatedAt:   time.Now(),
			Experiments: experiments.Experiments{experiments.EnableCodeEmbedding: experiments.Enabled},
		},
	}
)

// ReposForTestWithTenant returns a slice of test repos that conditionally includes the tenant's shortcode in the repo's owner login value.
func ReposForTestWithTenant() []github.Repository {
	if !tenantMode {
		return reposForTest
	}

	reposWithTenant := make([]github.Repository, len(reposForTest))
	for idx, repo := range reposForTest {
		repo.OwnerLogin = RepoOwnerLoginWithTenant(repo.OwnerLogin)
		reposWithTenant[idx] = repo
	}

	return reposWithTenant
}

func RepoOwnerLoginWithTenant(owner string) string {
	if !tenantMode {
		return owner
	}

	return fmt.Sprintf("%s_%s", owner, Tenant().Shortcode)
}

// Tenant returns a Tenant object if Tenant mode is enabled, otherwise nil,
// and is always safe to call regardless of the integration test mode.
func Tenant() *querypb.Tenant {
	if !tenantMode {
		return nil
	}

	return &querypb.Tenant{
		TenantId:  1,
		Slug:      "bigco",
		Shortcode: "bigco",
	}
}

type GitHubDB struct {
	repos map[types.RepoID]github.Repository
	mutex sync.Mutex
}

func NewGitHubDb() *GitHubDB {
	repos := map[types.RepoID]github.Repository{}
	for _, repo := range ReposForTestWithTenant() {
		repos[repo.ID] = repo
	}
	return &GitHubDB{repos: repos}
}

func (s *GitHubDB) AddRepository(repo github.Repository) {
	s.mutex.Lock()
	defer s.mutex.Unlock()

	if _, ok := s.repos[repo.ID]; ok {
		panic(fmt.Sprintf("repo %s already exists", repo.NWO()))
	}

	s.repos[repo.ID] = repo
}

func (s *GitHubDB) UpdateRepository(repoID types.RepoID, repo github.Repository) error {
	s.mutex.Lock()
	defer s.mutex.Unlock()

	_, ok := s.repos[repoID]
	if !ok {
		return fmt.Errorf("repo %d not found", repoID)
	}
	s.repos[repoID] = repo

	return nil
}

func (s *GitHubDB) DeleteRepository(repoID types.RepoID) {
	s.mutex.Lock()
	defer s.mutex.Unlock()

	repo, ok := s.repos[repoID]
	if !ok {
		panic(fmt.Sprintf("repo %d not found", repoID))
	}

	delete(s.repos, repo.ID)
}

func (s *GitHubDB) GetRepoByNWO(nwo types.NWO) (*github.Repository, bool) {
	s.mutex.Lock()
	defer s.mutex.Unlock()

	for _, repo := range s.repos {
		if repo.NWO() == nwo.String() {
			return &repo, true
		}
	}
	return nil, false
}

func (s *GitHubDB) GetRepoByID(repoID types.RepoID) (*github.Repository, bool) {
	s.mutex.Lock()
	defer s.mutex.Unlock()

	repo, ok := s.repos[types.RepoID(uint32(repoID))]
	return &repo, ok
}

func (s *GitHubDB) ListRepos() []github.Repository {
	s.mutex.Lock()
	defer s.mutex.Unlock()

	repos := make([]github.Repository, 0, len(s.repos))
	for _, repo := range s.repos {
		repos = append(repos, repo)
	}
	return repos
}

func (s *GitHubDB) Reset() {
	repos := map[types.RepoID]github.Repository{}
	for _, repo := range ReposForTestWithTenant() {
		repos[repo.ID] = repo
	}

	s.mutex.Lock()
	defer s.mutex.Unlock()
	s.repos = repos
}
