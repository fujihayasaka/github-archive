package spokestest

import (
	"context"
	"errors"
	"testing"

	"github.com/github/sweagentd/internal/spokes"
)

// TestBackwardsCompatibility verifies that the existing WithBlob API still works
func TestBackwardsCompatibility(t *testing.T) {
	// Create a client using the old API
	client := NewClient(t,
		WithBlob("test/path", []byte("test content")),
		WithBlob("another/path", []byte("another content")),
	)

	ctx := context.Background()

	// Test reading blobs for different repositories
	content1, commitSHA, err := client.ReadBlob(ctx, 1, "test/path")
	if err != nil {
		t.Fatalf("Failed to read blob for repo 1: %v", err)
	}
	if string(content1) != "test content" {
		t.Errorf("Expected 'test content', got %s", string(content1))
	}
	if commitSHA == "" {
		t.Error("Expected non-empty commit SHA")
	}

	// Same blob should be available for any repository (backwards compatibility)
	content2, commitSHA, err := client.ReadBlob(ctx, 2, "test/path")
	if err != nil {
		t.Fatalf("Failed to read blob for repo 2: %v", err)
	}
	if string(content2) != "test content" {
		t.Errorf("Expected 'test content', got %s", string(content2))
	}
	if commitSHA == "" {
		t.Error("Expected non-empty commit SHA")
	}

	// Test ListTrees
	files, commitSHA, err := client.ListTrees(ctx, 1, "")
	if err != nil {
		t.Fatalf("Failed to list trees: %v", err)
	}
	if len(files) != 2 {
		t.Errorf("Expected 2 files, got %d", len(files))
	}
	if commitSHA == "" {
		t.Error("Expected non-empty commit SHA")
	}
}

// TestNewRepoSpecificAPI verifies that the new repository-specific API works
func TestNewRepoSpecificAPI(t *testing.T) {
	// Create a client using the new API
	client := NewClient(t,
		WithRepoBlob(1, "repo1/file", []byte("repo1 content")),
		WithRepoBlob(2, "repo2/file", []byte("repo2 content")),
		WithBlob("global/file", []byte("global content")),
	)

	ctx := context.Background()

	// Test repository-specific blobs
	content1, commitSHA, err := client.ReadBlob(ctx, 1, "repo1/file")
	if err != nil {
		t.Fatalf("Failed to read repo1 blob: %v", err)
	}
	if string(content1) != "repo1 content" {
		t.Errorf("Expected 'repo1 content', got %s", string(content1))
	}
	if commitSHA == "" {
		t.Error("Expected non-empty commit SHA")
	}

	content2, commitSHA, err := client.ReadBlob(ctx, 2, "repo2/file")
	if err != nil {
		t.Fatalf("Failed to read repo2 blob: %v", err)
	}
	if string(content2) != "repo2 content" {
		t.Errorf("Expected 'repo2 content', got %s", string(content2))
	}
	if commitSHA == "" {
		t.Error("Expected non-empty commit SHA")
	}

	// Test that repo1 can't access repo2's file
	_, _, err = client.ReadBlob(ctx, 1, "repo2/file")
	if err == nil {
		t.Error("Expected error when accessing repo2 file from repo1")
	}

	// Test that global files are accessible from both repos
	globalContent1, commitSHA, err := client.ReadBlob(ctx, 1, "global/file")
	if err != nil {
		t.Fatalf("Failed to read global blob from repo1: %v", err)
	}
	if string(globalContent1) != "global content" {
		t.Errorf("Expected 'global content', got %s", string(globalContent1))
	}
	if commitSHA == "" {
		t.Error("Expected non-empty commit SHA")
	}

	globalContent2, commitSHA, err := client.ReadBlob(ctx, 2, "global/file")
	if err != nil {
		t.Fatalf("Failed to read global blob from repo2: %v", err)
	}
	if string(globalContent2) != "global content" {
		t.Errorf("Expected 'global content', got %s", string(globalContent2))
	}
	if commitSHA == "" {
		t.Error("Expected non-empty commit SHA")
	}
}

// TestRepoSpecificPrecedence verifies that repo-specific blobs take precedence over global ones
func TestRepoSpecificPrecedence(t *testing.T) {
	client := NewClient(t,
		WithBlob("shared/file", []byte("global content")),
		WithRepoBlob(1, "shared/file", []byte("repo1 specific content")),
	)

	ctx := context.Background()

	// Repo 1 should see its specific version
	content1, commitSHA, err := client.ReadBlob(ctx, 1, "shared/file")
	if err != nil {
		t.Fatalf("Failed to read blob for repo 1: %v", err)
	}
	if string(content1) != "repo1 specific content" {
		t.Errorf("Expected 'repo1 specific content', got %s", string(content1))
	}
	if commitSHA == "" {
		t.Error("Expected non-empty commit SHA")
	}

	// Repo 2 should see the global version
	content2, commitSHA, err := client.ReadBlob(ctx, 2, "shared/file")
	if err != nil {
		t.Fatalf("Failed to read blob for repo 2: %v", err)
	}
	if string(content2) != "global content" {
		t.Errorf("Expected 'global content', got %s", string(content2))
	}
	if commitSHA == "" {
		t.Error("Expected non-empty commit SHA")
	}
}

// TestNotFoundErrors verifies that appropriate errors are returned
func TestNotFoundErrors(t *testing.T) {
	client := NewClient(t,
		WithRepoBlob(1, "repo1/file", []byte("repo1 content")),
	)

	ctx := context.Background()

	// Test reading non-existent file
	_, _, err := client.ReadBlob(ctx, 1, "nonexistent/file")
	if !errors.Is(err, spokes.ErrNotFound) {
		t.Errorf("Expected ErrNotFound, got %v", err)
	}

	// Test reading from repo with no files
	_, _, err = client.ReadBlob(ctx, 2, "any/file")
	if !errors.Is(err, spokes.ErrNotFound) {
		t.Errorf("Expected ErrNotFound for empty repo, got %v", err)
	}

	// Test ListTrees for empty repo
	_, _, err = client.ListTrees(ctx, 2, "")
	if !errors.Is(err, spokes.ErrNotFound) {
		t.Errorf("Expected ErrNotFound for empty repo trees, got %v", err)
	}
}
