package gitsync

import (
	"time"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
)

// Option defines a function that configures a GitSyncer.
type Option func(*GitSyncer)

// WithGitRepoPath sets the repository path for the GitSyncer.
func WithGitRepoPath(path string) Option {
	return func(gs *GitSyncer) {
		gs.repoPath = path
	}
}

// WithMigrationTargetGitURL sets the target Git URL for the GitSyncer.
func WithMigrationTargetGitURL(url string) Option {
	return func(gs *GitSyncer) {
		gs.migrationTargetGitURL = url
	}
}

// WithLogger sets the logger for the GitSyncer.
func WithLogger(logger log.Logger) Option {
	return func(gs *GitSyncer) {
		gs.logger = logger.Named("gitsync")
	}
}

// WithStatter sets the stats client for the GitSyncer.
func WithStatter(statter stats.Client) Option {
	return func(gs *GitSyncer) {
		gs.statter = statter
	}
}

// WithSyncInterval sets the sync interval for the GitSyncer.
func WithSyncInterval(interval time.Duration) Option {
	return func(gs *GitSyncer) {
		gs.syncInterval = interval
	}
}
