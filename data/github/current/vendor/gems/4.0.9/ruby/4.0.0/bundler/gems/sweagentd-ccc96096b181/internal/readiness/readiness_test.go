package readiness

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	"github.com/github/sweagentd/internal/goerrors"
)

type mockHealthChecker struct {
	shouldFail bool
}

func (m *mockHealthChecker) HealthCheck(_ context.Context) error {
	if m.shouldFail {
		return goerrors.New("health check failed")
	}
	return nil
}

func fileExists(path string) bool {
	_, err := os.Stat(path)
	return !os.IsNotExist(err)
}

func TestProbe_MarkReady(t *testing.T) {
	t.Run("creates probe file without health checker", func(t *testing.T) {
		tmpDir := t.TempDir()
		probePath := filepath.Join(tmpDir, "ready")

		probe := NewProbe(WithFilePath(probePath))
		err := probe.MarkReady(context.Background())
		if err != nil {
			t.Fatalf("expected no error, got %v", err)
		}

		if !fileExists(probePath) {
			t.Fatal("expected probe file to exist")
		}
	})

	t.Run("creates probe file when health check passes", func(t *testing.T) {
		tmpDir := t.TempDir()
		probePath := filepath.Join(tmpDir, "ready")

		checker := &mockHealthChecker{shouldFail: false}
		probe := NewProbe(WithFilePath(probePath), WithHealthChecker(checker))
		err := probe.MarkReady(context.Background())
		if err != nil {
			t.Fatalf("expected no error, got %v", err)
		}

		if !fileExists(probePath) {
			t.Fatal("expected probe file to exist")
		}
	})

	t.Run("does not create probe file when health check fails", func(t *testing.T) {
		tmpDir := t.TempDir()
		probePath := filepath.Join(tmpDir, "ready")

		checker := &mockHealthChecker{shouldFail: true}
		probe := NewProbe(WithFilePath(probePath), WithHealthChecker(checker))
		err := probe.MarkReady(context.Background())
		if err == nil {
			t.Fatal("expected error, got nil")
		}

		if fileExists(probePath) {
			t.Fatal("expected probe file to not exist")
		}
	})

	t.Run("checks multiple health checkers", func(t *testing.T) {
		tmpDir := t.TempDir()
		probePath := filepath.Join(tmpDir, "ready")

		healthyChecker := &mockHealthChecker{shouldFail: false}
		failingChecker := &mockHealthChecker{shouldFail: true}
		probe := NewProbe(
			WithFilePath(probePath),
			WithHealthChecker(healthyChecker),
			WithHealthChecker(failingChecker),
		)
		err := probe.MarkReady(context.Background())
		if err == nil {
			t.Fatal("expected error when one checker fails, got nil")
		}

		if fileExists(probePath) {
			t.Fatal("expected probe file to not exist")
		}
	})

	t.Run("handles nil health checker gracefully", func(t *testing.T) {
		tmpDir := t.TempDir()
		probePath := filepath.Join(tmpDir, "ready")

		probe := NewProbe(WithFilePath(probePath), WithHealthChecker(nil))
		err := probe.MarkReady(context.Background())
		if err != nil {
			t.Fatalf("expected no error with nil checker, got %v", err)
		}

		if !fileExists(probePath) {
			t.Fatal("expected probe file to exist")
		}
	})
}

func TestProbe_MarkNotReady(t *testing.T) {
	t.Run("removes probe file if exists", func(t *testing.T) {
		tmpDir := t.TempDir()
		probePath := filepath.Join(tmpDir, "ready")

		// Create the file first
		_, err := os.Create(probePath)
		if err != nil {
			t.Fatalf("failed to create probe file: %v", err)
		}

		probe := NewProbe(WithFilePath(probePath))
		err = probe.MarkNotReady()
		if err != nil {
			t.Fatalf("expected no error, got %v", err)
		}

		if fileExists(probePath) {
			t.Fatal("expected probe file to not exist")
		}
	})

	t.Run("succeeds if file does not exist", func(t *testing.T) {
		tmpDir := t.TempDir()
		probePath := filepath.Join(tmpDir, "ready")

		probe := NewProbe(WithFilePath(probePath))
		err := probe.MarkNotReady()
		if err != nil {
			t.Fatalf("expected no error when file doesn't exist, got %v", err)
		}
	})
}
