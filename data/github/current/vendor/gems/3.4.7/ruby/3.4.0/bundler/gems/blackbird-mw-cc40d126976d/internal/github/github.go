package github

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	gh "github.com/google/go-github/github"

	"github.com/github/blackbird-mw/internal/experiments"
	"github.com/github/blackbird-mw/internal/types"
)

// See https://cs.github.com/github/github/blob/baedb4ab5416773374de7401c6ba144285e6b1b0/app/api/app/error_dependency.rb#L222
// for where these errors are generated for the different repository status cases.
var (
	ErrRepoNotFound = errors.New("repository not found")
	ErrRepoDisabled = errors.New("repository disabled")
	ErrRepoBlocked  = errors.New("repository blocked")
)

//go:generate counterfeiter . InternalAPIClient
type InternalAPIClient interface {
	GetRepository(ctx context.Context, repoID types.RepoID) (*Repository, error)
	GetRepositoryByNWO(ctx context.Context, nwo types.NWO) (*Repository, error)
	GetUser(ctx context.Context, login string) (*gh.User, error)
	GetRepositoriesByIds(ctx context.Context, repoIDs []types.RepoID) ([]*Repository, error)
	GetRepositoriesByCursor(ctx context.Context, cursor string, limit int) ([]*Repository, string /* next cursor */, error)

	GetPullsForCommit(ctx context.Context, nwo types.NWO, commitSHA string) ([]*gh.PullRequest, error)
}

type Repository struct {
	ID              types.RepoID            `json:"id"`
	NetworkID       types.NetworkID         `json:"network_id"`
	OwnerID         uint32                  `json:"owner_id"`
	OwnerLogin      string                  `json:"owner_login"`
	OwnerSpammy     bool                    `json:"owner_spammy"`
	Name            string                  `json:"name"`
	Public          bool                    `json:"public"`
	Archived        bool                    `json:"archived"`
	DiskUsage       uint64                  `json:"disk_usage"` // in kilobytes for some reason
	PushedAt        time.Time               `json:"pushed_at"`
	CreatedAt       time.Time               `json:"created_at"`
	LicenseName     string                  `json:"license_name"`
	NumWatchers     int32                   `json:"num_watchers"`
	NumStars        int32                   `json:"num_stars"`
	HasReadme       bool                    `json:"has_readme"`
	PublicForkCount int32                   `json:"public_fork_count"`
	PayingCustomer  bool                    `json:"paying_customer"`
	IsFork          bool                    `json:"fork"`
	Experiments     experiments.Experiments `json:"experiments"`
	UpdatedAt       time.Time               `json:"updated_at"`
	RepoSeqNo       types.RepoSeqNo         `json:"seq_no"`
}

func (r *Repository) NWO() string {
	return fmt.Sprintf("%s/%s", r.OwnerLogin, r.Name)
}

// DiskUsageBytes returns disk usage in a useful unit.
func (r *Repository) DiskUsageBytes() uint64 {
	return r.DiskUsage * 1024
}

func ParseUserLogin(user *gh.User) string {
	login := user.GetLogin()
	if strings.HasSuffix(login, "[bot]") {
		login = fmt.Sprintf("app/%s", strings.TrimSuffix(login, "[bot]"))
	}
	return login
}
