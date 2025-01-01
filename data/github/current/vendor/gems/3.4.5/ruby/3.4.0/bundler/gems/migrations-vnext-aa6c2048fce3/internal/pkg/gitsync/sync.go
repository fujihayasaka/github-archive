// Package gitsync is a package that handles syncing git data to the migration
// target.
package gitsync

import (
	"bufio"
	"context"
	"embed"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sync"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
)

//go:embed scripts/*
var scripts embed.FS

// GitSyncer is a struct defining the repo to sync and the migration target.
type GitSyncer struct {
	repoPath              string
	migrationTargetGitURL string
	syncInterval          time.Duration
	logger                log.Logger
	statter               stats.Client
	doSyncFunc            func() error
	done                  chan struct{}
	cancel                context.CancelFunc
}

// New creates a new GitSyncer with the provided options.
func New(opts ...Option) (*GitSyncer, error) {
	gs := &GitSyncer{
		logger:  log.NewNullLogger(),
		statter: stats.NullStatter,
	}
	gs.doSyncFunc = gs.doSync

	for _, opt := range opts {
		opt(gs)
	}

	if err := gs.validate(); err != nil {
		return gs, fmt.Errorf("invalid configuration provided: %w", err)
	}

	return gs, nil
}

// Start starts the git sync and blocks until it is stopped
func (gs *GitSyncer) Start(ctx context.Context) error {
	gs.logger.Info("starting git sync", kvp.Duration("interval", gs.syncInterval))

	ticker := time.NewTicker(gs.syncInterval)
	defer ticker.Stop()

	if err := gs.doSyncFunc(); err != nil {
		// allow failures. log and continue
		gs.logger.WithError(err).Error("initial git sync failed")
	}

	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-ticker.C:
			if err := gs.doSync(); err != nil {
				// allow failures. log and continue
				gs.logger.WithError(err).Error("git sync failed")
			}
		}
	}
}

// StartAsync starts the git sync in the background and returns a channel that
// will be closed when syncing is stopped
func (gs *GitSyncer) StartAsync(ctx context.Context) (chan struct{}, error) {
	done := make(chan struct{})
	ctxWithCancel, cancel := context.WithCancel(ctx)

	go func() {
		defer close(done)
		if err := gs.Start(ctxWithCancel); err != nil && !errors.Is(err, context.Canceled) {
			gs.logger.WithError(err).Error("error during git sync")
		}
	}()

	gs.done = done
	gs.cancel = cancel

	return done, nil
}

// Shutdown stops the git sync after ensuring one final sync is completed
func (gs *GitSyncer) Shutdown() {
	gs.logger.Info("initiating final git sync")

	// run a final sync and wait for it to complete
	if err := gs.doSync(); err != nil {
		gs.logger.WithError(err).Error("final git sync failed")
	}

	gs.logger.Info("final git sync completed, shutting down")

	gs.cancel()

	<-gs.done
	gs.logger.Info("git sync shut down")
}

func (gs *GitSyncer) doSync() error {
	scriptsDir, err := gs.extractScripts()
	if err != nil {
		return fmt.Errorf("failed to extract scripts: %w", err)
	}

	cmd := exec.Command(filepath.Join(scriptsDir, "sync-repo"))
	cmd.Dir = gs.repoPath
	cmd.Env = append(os.Environ(), fmt.Sprintf("MIGRATION_TARGET_URL=%s", gs.migrationTargetGitURL))

	if err := gs.handleCommandOutput(cmd); err != nil {
		return fmt.Errorf("git sync command failed: %w", err)
	}

	gs.logger.Info("git sync complete")
	return nil
}

func (gs *GitSyncer) handleCommandOutput(cmd *exec.Cmd) error {
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return fmt.Errorf("failed to get stdout pipe: %w", err)
	}

	stderr, err := cmd.StderrPipe()
	if err != nil {
		return fmt.Errorf("failed to get stderr pipe: %w", err)
	}

	if err := cmd.Start(); err != nil {
		return fmt.Errorf("failed to start command: %w", err)
	}

	var wg sync.WaitGroup
	wg.Add(2)

	go func() {
		defer wg.Done()
		scanner := bufio.NewScanner(stdout)
		for scanner.Scan() {
			line := scanner.Text()
			gs.logger.Info("git sync output", kvp.String("message", line))
		}
	}()

	go func() {
		defer wg.Done()
		scanner := bufio.NewScanner(stderr)
		for scanner.Scan() {
			line := scanner.Text()
			gs.logger.Error("git sync error", kvp.String("message", line))
		}
	}()

	cmdErr := cmd.Wait()

	wg.Wait()

	return cmdErr
}

func (gs *GitSyncer) extractScripts() (string, error) {
	tempDir := filepath.Join(os.TempDir(), "ghes-migrator-scripts")
	if err := os.MkdirAll(tempDir, 0o700); err != nil {
		return "", fmt.Errorf("failed to create temp dir: %w", err)
	}

	entries, err := scripts.ReadDir("scripts")
	if err != nil {
		return "", fmt.Errorf("failed to read embedded scripts: %w", err)
	}

	for _, entry := range entries {
		content, err := scripts.ReadFile(filepath.Join("scripts", entry.Name()))
		if err != nil {
			return "", fmt.Errorf("failed to read script %s: %w", entry.Name(), err)
		}

		scriptPath := filepath.Join(tempDir, entry.Name())
		//nolint:gosec // Execute permission required for running migration scripts
		if err := os.WriteFile(scriptPath, content, 0o700); err != nil {
			return "", fmt.Errorf("failed to write script %s: %w", entry.Name(), err)
		}
	}

	return tempDir, nil
}

func (gs *GitSyncer) validate() error {
	if gs.repoPath == "" {
		return errors.New("git repo path is required")
	}
	if gs.migrationTargetGitURL == "" {
		return errors.New("migration target git URL is required")
	}
	if gs.syncInterval == 0 {
		return errors.New("sync interval is required")
	}
	return nil
}
