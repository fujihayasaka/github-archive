package gitsync

import (
	"context"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

const testSyncInterval = 1 * time.Millisecond

func TestNew(t *testing.T) {
	tests := []struct {
		name    string
		opts    []Option
		wantErr bool
	}{
		{
			name:    "no options",
			opts:    []Option{},
			wantErr: true,
		},
		{
			name: "valid options",
			opts: []Option{
				WithGitRepoPath("/path/to/repo"),
				WithMigrationTargetGitURL("git://example.com/repo.git"),
				WithSyncInterval(5 * time.Second),
			},
			wantErr: false,
		},
		{
			name: "missing repo path",
			opts: []Option{
				WithMigrationTargetGitURL("git://example.com/repo.git"),
				WithSyncInterval(5 * time.Second),
			},
			wantErr: true,
		},
		{
			name: "missing target URL",
			opts: []Option{
				WithGitRepoPath("/path/to/repo"),
				WithSyncInterval(5 * time.Second),
			},
			wantErr: true,
		},
		{
			name: "missing sync interval",
			opts: []Option{
				WithGitRepoPath("/path/to/repo"),
				WithMigrationTargetGitURL("git://example.com/repo.git"),
			},
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := New(tt.opts...)
			if tt.wantErr {
				assert.Error(t, err)
			} else {
				assert.NoError(t, err)
			}
		})
	}
}

func TestGitSyncer_Start(t *testing.T) {
	gs := newTestGitSyncer(t)

	ctx, cancel := context.WithTimeout(context.Background(), 3*testSyncInterval)
	defer cancel()

	// run in a goroutine to make sure it blocks
	startDone := make(chan error, 1)
	go func() { startDone <- gs.Start(ctx) }()

	time.Sleep(testSyncInterval)

	// Start shouldn't have exited yet
	select {
	case err := <-startDone:
		assert.Fail(t, "Start returned early", "got error: %v", err)
	default:
		// expected: Start is still running
	}

	// wait for timeout
	select {
	case err := <-startDone:
		require.ErrorIs(t, err, context.DeadlineExceeded, "Start did not return DeadlineExceeded")
	case <-time.After(10 * testSyncInterval):
		assert.Fail(t, "Start did not exit after context timeout")
	}
}

func TestGitSyncer_StartAsync(t *testing.T) {
	gs := newTestGitSyncer(t)

	done, err := gs.StartAsync(context.Background())
	require.NoError(t, err, "StartAsync failed to start")

	select {
	case <-done:
		assert.Fail(t, "done channel was closed prematurely")
	default:
		// expected: channel is open since sync hasn't been stopped
	}

	gs.Shutdown()
	<-done
}

func TestGitSyncer_Shutdown(t *testing.T) {
	gs := newTestGitSyncer(t)

	syncCalled := false
	gs.doSyncFunc = func() error {
		syncCalled = true
		return nil
	}

	done, err := gs.StartAsync(context.Background())
	require.NoError(t, err, "StartAsync failed to start")

	gs.Shutdown()

	require.True(t, syncCalled, "Shutdown did not trigger a final sync")

	// verify done channel is closed after shutdown
	select {
	case <-done:
		// expected: channel closed after shutdown
	case <-time.After(2 * testSyncInterval):
		assert.Fail(t, "done channel was not closed after shutdown")
	}
}

// newTestGitSyncer creates a GitSyncer with a mocked doSyncFunc for testing
func newTestGitSyncer(t *testing.T) *GitSyncer {
	t.Helper()

	gs, err := New(
		WithGitRepoPath("/path/to/repo"),
		WithMigrationTargetGitURL("git://example.com/repo.git"),
		WithSyncInterval(testSyncInterval),
	)
	require.NoError(t, err, "failed to create GitSyncer")

	gs.doSyncFunc = func() error { return nil }

	return gs
}
