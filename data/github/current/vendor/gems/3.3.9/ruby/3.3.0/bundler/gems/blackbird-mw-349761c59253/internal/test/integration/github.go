package integration

import (
	"encoding/json"
	"fmt"
	"html"
	"io"
	"net/http"
	"os"
	"strconv"
	"strings"
	"sync"
	"testing"

	"github.com/github/blackbird-mw/internal/auth"
	"github.com/github/blackbird-mw/internal/github"
	"github.com/github/blackbird-mw/internal/types"
)

const (
	getRepoPrefix           = "/internal/blackbird/repositories/"
	accessibleResourcesPath = "/internal/blackbird/accessible_resources"
	allAccessToken          = "all-access-token"
)

// Implements http.Handler to mock Blackbird's internal GitHub API.
type GitHubServer struct {
	t     *testing.T
	repos map[types.RepoID]github.Repository
	mutex sync.Mutex
}

func NewGitHubServer(t *testing.T, repos ...github.Repository) *GitHubServer {
	repoMap := map[types.RepoID]github.Repository{}
	for _, repo := range repos {
		repoMap[repo.ID] = repo
	}

	return &GitHubServer{t: t, repos: repoMap}
}

func (s *GitHubServer) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	s.log("GitHub Internal API Server: %s %s", r.Method, r.URL.String())

	switch {
	case isGetRepository(r):
		s.handleGetRepository(w, r)
	case isAccessibleResources(r):
		s.handleAccessibleResources(w, r)
	default:
		http.Error(w, fmt.Sprintf("Unhandled request: %s %s", r.Method, html.EscapeString(r.URL.Path)), 500)
	}
}

// Return the repository for an ID. Panics if not found. This repo is accurate
// when returned but can immediately become out of date.
func (s *GitHubServer) RepositoryForID(repoID types.RepoID) github.Repository {
	s.mutex.Lock()
	defer s.mutex.Unlock()

	repo, ok := s.repos[repoID]
	if !ok {
		panic(fmt.Sprintf("repo %d not found", repoID))
	}
	return repo
}

func (s *GitHubServer) AddRepository(repo github.Repository) {
	s.mutex.Lock()
	defer s.mutex.Unlock()

	if _, ok := s.repos[repo.ID]; ok {
		panic(fmt.Sprintf("repo %s already exists", repo.NWO()))
	}

	s.repos[repo.ID] = repo
}

func (s *GitHubServer) UpdateRepository(repoID types.RepoID, cb func(repo github.Repository) github.Repository) github.Repository {
	s.mutex.Lock()
	defer s.mutex.Unlock()

	repo, ok := s.repos[repoID]
	if !ok {
		panic(fmt.Sprintf("repo %d not found", repoID))
	}
	result := cb(repo)
	s.repos[result.ID] = result

	return result
}

func (s *GitHubServer) DeleteRepository(repoID types.RepoID) {
	s.mutex.Lock()
	defer s.mutex.Unlock()

	repo, ok := s.repos[repoID]
	if !ok {
		panic(fmt.Sprintf("repo %d not found", repoID))
	}

	delete(s.repos, repo.ID)
}

func (s *GitHubServer) getRepoByNWO(nwo types.NWO) (*github.Repository, bool) {
	s.mutex.Lock()
	defer s.mutex.Unlock()

	for _, repo := range s.repos {
		if repo.NWO() == nwo.String() {
			return &repo, true
		}
	}
	return nil, false
}

func (s *GitHubServer) getRepoByID(repoID types.RepoID) (*github.Repository, bool) {
	s.mutex.Lock()
	defer s.mutex.Unlock()

	repo, ok := s.repos[types.RepoID(uint32(repoID))]
	return &repo, ok
}

func (s *GitHubServer) handleGetRepository(w http.ResponseWriter, r *http.Request) {
	var ok bool
	var repo *github.Repository
	identifier := strings.TrimPrefix(r.URL.Path, getRepoPrefix)
	nwo, err := types.NewNWO(identifier)
	if err != nil {
		repoID, err := strconv.ParseUint(identifier, 10, 32)
		if err != nil {
			http.Error(w, fmt.Sprintf("Invalid repo ID %s", identifier), 400)
			return
		}
		repo, ok = s.getRepoByID(types.RepoID(repoID))
	} else {
		repo, ok = s.getRepoByNWO(nwo)
	}

	if !ok {
		http.Error(w, fmt.Sprintf("Unknown repo: %s", identifier), 404)
		return
	}

	out, err := json.Marshal(repo)
	if err != nil {
		http.Error(w, fmt.Sprintf("Could not marshal JSON for repo %d: %+v", repo.ID, err), 500)
		return
	}

	w.WriteHeader(200)
	w.Header().Add("Content-Type", "application/json")
	_, err = w.Write(out)
	if err != nil {
		s.t.Fatalf("fatal error serializing JSON: %+v", err)
	}

	s.log("get repository: success: id=%d, json=%s", repo.ID, string(out))
}

func (s *GitHubServer) handleAccessibleResources(w http.ResponseWriter, r *http.Request) {
	res := auth.AccessibleResourcesResponse{}

	body, err := io.ReadAll(r.Body)
	if err != nil {
		http.Error(w, "Failed to read request body", http.StatusInternalServerError)
		return
	}
	defer r.Body.Close()

	var requestData auth.AccessibleResourcesRequest
	err = json.Unmarshal(body, &requestData)
	if err != nil {
		http.Error(w, "Failed to unmarshal JSON", http.StatusBadRequest)
		return
	}

	token := requestData.Token
	for id, repo := range s.repos {
		if !repo.Public && token == allAccessToken {
			res.AccessibleRepositoryIDs = append(res.AccessibleRepositoryIDs, int64(id))
		}
	}

	out, err := json.Marshal(res)
	if err != nil {
		http.Error(w, fmt.Sprintf("Could not marshal JSON for accessible resources: %+v", err), 500)
		return
	}

	w.WriteHeader(200)
	w.Header().Add("Content-Type", "application/json")
	_, err = w.Write(out)
	if err != nil {
		s.t.Fatalf("fatal error serializing JSON: %+v", err)
	}
}

func (s *GitHubServer) log(format string, args ...any) {
	if os.Getenv("LOG_GITHUB_API") != "" {
		s.t.Logf(format, args...)
	}
}

func isGetRepository(r *http.Request) bool {
	return r.Method == http.MethodGet && strings.HasPrefix(r.URL.Path, getRepoPrefix)
}

func isAccessibleResources(r *http.Request) bool {
	return r.Method == http.MethodPost && r.URL.Path == accessibleResourcesPath
}
