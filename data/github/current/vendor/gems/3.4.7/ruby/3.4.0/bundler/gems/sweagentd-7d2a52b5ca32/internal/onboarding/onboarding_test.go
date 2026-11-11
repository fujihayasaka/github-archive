package onboarding

import (
	"context"
	"errors"
	"net/http"
	"strings"
	"testing"

	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/jobs"
	gg "github.com/google/go-github/v75/github"
	"github.com/stretchr/testify/require"
)

// mockClientForEmpty returns 404 for GetContents calls, simulating no instruction files exist
type mockClientForEmpty struct {
	github.NoopClient
}

func (m *mockClientForEmpty) GetContents(ctx context.Context, owner, repo, path string, opts *gg.RepositoryContentGetOptions) (fileContent *gg.RepositoryContent, dirContent []*gg.RepositoryContent, err error) {
	return nil, nil, &gg.ErrorResponse{
		Response: &http.Response{StatusCode: http.StatusNotFound},
	}
}

type mockJobStore struct {
	existingJob bool
}

func (m *mockJobStore) GetJobForActorOnboarding(ctx context.Context, owner, repo, actor int64) (*jobs.Job, error) {
	if m.existingJob {
		return &jobs.Job{
			ActorID:           123,
			RepoID:            456,
			OwnerID:           789,
			RepoOwner:         "testowner",
			RepoName:          "testrepo",
			PullRequestNumber: 1,
		}, nil
	}
	return nil, nil
}

func TestCreateOnboardingCommentIfNeeded(t *testing.T) {
	ctx := context.Background()
	jobStore := &mockJobStore{existingJob: false}
	job := &jobs.Job{
		ActorID:           123,
		RepoID:            456,
		OwnerID:           789,
		RepoOwner:         "testowner",
		RepoName:          "testrepo",
		PullRequestNumber: 1,
	}

	t.Run("feature flag disabled", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{featureFlagName: false})
		ghClient := &github.NoopClient{}

		comment, err := CreateOnboardingCommentIfNeeded(ctx, ffClient, jobStore, ghClient, job)
		require.NoError(t, err)
		require.Nil(t, comment)
		require.True(t, ghClient.HasNMethodCalls("CreateComment", 0))
	})

	t.Run("successful comment creation", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{featureFlagName: true})
		ghClient := &mockClientForEmpty{}

		comment, err := CreateOnboardingCommentIfNeeded(ctx, ffClient, jobStore, ghClient, job)
		require.NoError(t, err)
		require.NotNil(t, comment)
		require.True(t, ghClient.HasNMethodCalls("CreateComment", 1))
	})

	t.Run("empty repo owner error", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{featureFlagName: true})
		// Use custom mock that returns 404 for GetContents to simulate no instruction files
		ghClient := &mockClientForEmpty{}
		emptyOwnerJob := &jobs.Job{
			ActorID: 123, RepoID: 456, OwnerID: 789,
			RepoOwner: "", RepoName: "testrepo",
			PullRequestNumber: 1,
		}

		_, err := CreateOnboardingCommentIfNeeded(ctx, ffClient, jobStore, ghClient, emptyOwnerJob)
		require.Error(t, err)
		require.Contains(t, err.Error(), "repoOwner and repoName cannot be empty")
	})

	t.Run("empty repo name error", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{featureFlagName: true})
		// Use custom mock that returns 404 for GetContents to simulate no instruction files
		ghClient := &mockClientForEmpty{}
		emptyNameJob := &jobs.Job{
			ActorID: 123, RepoID: 456, OwnerID: 789,
			RepoOwner: "testowner", RepoName: "",
			PullRequestNumber: 1,
		}

		_, err := CreateOnboardingCommentIfNeeded(ctx, ffClient, jobStore, ghClient, emptyNameJob)
		require.Error(t, err)
		require.Contains(t, err.Error(), "repoOwner and repoName cannot be empty")
	})
}

func TestExistingJobWithOnboardingComment(t *testing.T) {
	ctx := context.Background()
	jobStore := &mockJobStore{existingJob: true}
	job := &jobs.Job{
		ActorID:           123,
		RepoID:            456,
		OwnerID:           789,
		RepoOwner:         "testowner",
		RepoName:          "testrepo",
		PullRequestNumber: 1,
	}

	t.Run("existing job with onboarding comment", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{featureFlagName: true})
		ghClient := &github.NoopClient{}
		comment, err := CreateOnboardingCommentIfNeeded(ctx, ffClient, jobStore, ghClient, job)

		require.NoError(t, err)
		require.Nil(t, comment)
		require.True(t, ghClient.HasNMethodCalls("CreateComment", 0))
	})
}

func TestSubstituteOnboardingTipIfEnabled(t *testing.T) {
	ctx := context.Background()
	job := &jobs.Job{ActorID: 123, RepoID: 456, OwnerID: 789}

	t.Run("feature flag disabled", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{featureFlagName: false})
		tip := "Some tip with <Onboard this repo>"

		result := SubstituteOnboardingTipIfEnabled(ctx, ffClient, job, tip)
		require.Equal(t, tip, result)
	})

	t.Run("no magic string", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{featureFlagName: true})
		tip := "Some tip without magic string"

		result := SubstituteOnboardingTipIfEnabled(ctx, ffClient, job, tip)
		require.Equal(t, tip, result)
	})

	t.Run("magic string present", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{featureFlagName: true})
		tip := "Some tip with <Onboard this repo> magic string"

		result := SubstituteOnboardingTipIfEnabled(ctx, ffClient, job, tip)
		require.Equal(t, onboardingPrompt, result)
	})

	t.Run("multiple magic strings", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{featureFlagName: true})
		tip := "First <Onboard this repo> and second <Onboard this repo>"

		result := SubstituteOnboardingTipIfEnabled(ctx, ffClient, job, tip)
		require.Equal(t, onboardingPrompt, result)
	})
}

func TestSubstituteJobParameters(t *testing.T) {
	tests := []struct {
		name, body, repoOwner, repoName, expected, expectedError string
	}{
		{"no placeholders", "Simple body", "owner", "repo", "Simple body", ""},
		{"repo owner only", "Owner: {repo_owner}", "owner", "repo", "Owner: owner", ""},
		{"repo name only", "Name: {repo_name}", "owner", "repo", "Name: repo", ""},
		{"both placeholders", "{repo_owner}/{repo_name}", "owner", "repo", "owner/repo", ""},
		{"multiple same", "{repo_owner} {repo_owner}", "owner", "repo", "owner owner", ""},
		{"multiple both", "{repo_owner}/{repo_name} {repo_owner}/{repo_name}", "owner", "repo", "owner/repo owner/repo", ""},
		{"empty owner with placeholder", "{repo_owner}", "", "repo", "", "repoOwner and repoName cannot be empty"},
		{"empty name with placeholder", "{repo_name}", "owner", "", "", "repoOwner and repoName cannot be empty"},
		{"empty without placeholders", "No placeholders", "", "", "No placeholders", ""},
		{"special chars", "{repo_owner}/{repo_name}", "test-owner", "test_repo.name", "test-owner/test_repo.name", ""},
		{"case sensitive", "{REPO_OWNER} {repo_owner}", "owner", "repo", "{REPO_OWNER} owner", ""},
		{"partial matches", "{repo_owner_id} {repo_owner}", "owner", "repo", "{repo_owner_id} owner", ""},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result, err := SubstituteJobParameters(tt.body, tt.repoOwner, tt.repoName)

			if tt.expectedError != "" {
				require.Error(t, err)
				require.Contains(t, err.Error(), tt.expectedError)
			} else {
				require.NoError(t, err)
				require.Equal(t, tt.expected, result)
			}
		})
	}
}

func TestEdgeCases(t *testing.T) {
	ctx := context.Background()

	t.Run("zero values", func(t *testing.T) {
		job := &jobs.Job{}
		ffClient := featureflags.NewNoopClient(map[string]bool{featureFlagName: true})

		result := SubstituteOnboardingTipIfEnabled(ctx, ffClient, job, "no magic string")
		require.Equal(t, "no magic string", result)
	})

	t.Run("long strings", func(t *testing.T) {
		longOwner := "a-very-long-repository-owner-name-that-exceeds-normal-length-limits"
		longRepo := "a-very-long-repository-name-that-also-exceeds-normal-length-limits"

		result, err := SubstituteJobParameters("{repo_owner}/{repo_name}", longOwner, longRepo)
		require.NoError(t, err)
		require.Equal(t, longOwner+"/"+longRepo, result)
	})

	t.Run("unicode", func(t *testing.T) {
		result, err := SubstituteJobParameters("{repo_owner}/{repo_name} 🚀", "owner", "repo")
		require.NoError(t, err)
		require.Equal(t, "owner/repo 🚀", result)
	})
}

// Mock clients for testing different scenarios

// mockClientWithInstructions returns content for the instructions file
type mockClientWithInstructions struct {
	github.NoopClient
}

func (m *mockClientWithInstructions) GetContents(ctx context.Context, owner, repo, path string, opts *gg.RepositoryContentGetOptions) (fileContent *gg.RepositoryContent, dirContent []*gg.RepositoryContent, err error) {
	if path == ".github/copilot-instructions.md" {
		return &gg.RepositoryContent{
			Name:     gg.Ptr("instructions.md"),
			Content:  gg.Ptr("VGVzdCBpbnN0cnVjdGlvbnM="), // base64 encoded "Test instructions"
			Encoding: gg.Ptr("base64"),
		}, nil, nil
	}
	return nil, nil, &gg.ErrorResponse{
		Response: &http.Response{StatusCode: http.StatusNotFound},
	}
}

// mockClientWithInstructionsDir returns content for the setup yaml file
type mockClientWithInstructionsDir struct {
	github.NoopClient
}

func (m *mockClientWithInstructionsDir) GetContents(ctx context.Context, owner, repo, path string, opts *gg.RepositoryContentGetOptions) (fileContent *gg.RepositoryContent, dirContent []*gg.RepositoryContent, err error) {
	if path == ".github/instructions" {
		// Return directory contents with an instructions file
		return nil, []*gg.RepositoryContent{
			{
				Name: gg.Ptr("test.instructions.md"),
				Type: gg.Ptr("file"),
			},
		}, nil
	}
	if path == ".github/instructions/test.instructions.md" {
		return &gg.RepositoryContent{
			Name:     gg.Ptr("test.instructions.md"),
			Content:  gg.Ptr("VGVzdCBpbnN0cnVjdGlvbnM="), // base64 encoded "Test instructions"
			Encoding: gg.Ptr("base64"),
		}, nil, nil
	}
	return nil, nil, &gg.ErrorResponse{
		Response: &http.Response{StatusCode: http.StatusNotFound},
	}
}

// mockClientWithNestedInstructionsDir returns content for nested instructions files
type mockClientWithNestedInstructionsDir struct {
	github.NoopClient
}

func (m *mockClientWithNestedInstructionsDir) GetContents(ctx context.Context, owner, repo, path string, opts *gg.RepositoryContentGetOptions) (fileContent *gg.RepositoryContent, dirContent []*gg.RepositoryContent, err error) {
	if path == ".github/instructions" {
		// Return directory contents with a subdirectory
		return nil, []*gg.RepositoryContent{
			{
				Name: gg.Ptr("subdir"),
				Type: gg.Ptr("dir"),
			},
		}, nil
	}
	if path == ".github/instructions/subdir" {
		// Return subdirectory contents with an instructions file
		return nil, []*gg.RepositoryContent{
			{
				Name: gg.Ptr("nested.instructions.md"),
				Type: gg.Ptr("file"),
			},
		}, nil
	}
	if path == ".github/instructions/subdir/nested.instructions.md" {
		return &gg.RepositoryContent{
			Name:     gg.Ptr("nested.instructions.md"),
			Content:  gg.Ptr("TmVzdGVkIGluc3RydWN0aW9ucw=="), // base64 encoded "Nested instructions"
			Encoding: gg.Ptr("base64"),
		}, nil, nil
	}
	return nil, nil, &gg.ErrorResponse{
		Response: &http.Response{StatusCode: http.StatusNotFound},
	}
}

// mockClientWithError returns a non-404 error for all GetContents calls
type mockClientWithError struct {
	github.NoopClient
}

func (m *mockClientWithError) GetContents(ctx context.Context, owner, repo, path string, opts *gg.RepositoryContentGetOptions) (fileContent *gg.RepositoryContent, dirContent []*gg.RepositoryContent, err error) {
	return nil, nil, &gg.ErrorResponse{
		Response: &http.Response{StatusCode: http.StatusInternalServerError},
		Message:  "Server error",
	}
}

// mockClientFailComment simulates comment creation failure
type mockClientFailComment struct {
	github.NoopClient
}

func (m *mockClientFailComment) GetContents(ctx context.Context, owner, repo, path string, opts *gg.RepositoryContentGetOptions) (fileContent *gg.RepositoryContent, dirContent []*gg.RepositoryContent, err error) {
	return nil, nil, &gg.ErrorResponse{
		Response: &http.Response{StatusCode: http.StatusNotFound},
	}
}

func (m *mockClientFailComment) CreateComment(ctx context.Context, repoID int64, issueOrPRNumber int, body string) (*gg.IssueComment, error) {
	return nil, errors.New("failed to create comment")
}

// mockClientEmptyContent returns empty/whitespace-only content
type mockClientEmptyContent struct {
	github.NoopClient
}

func (m *mockClientEmptyContent) GetContents(ctx context.Context, owner, repo, path string, opts *gg.RepositoryContentGetOptions) (fileContent *gg.RepositoryContent, dirContent []*gg.RepositoryContent, err error) {
	return &gg.RepositoryContent{
		Name:     gg.Ptr("empty.md"),
		Content:  gg.Ptr("ICAgIA=="), // base64 encoded "    " (whitespace only)
		Encoding: gg.Ptr("base64"),
	}, nil, nil
}

// mockClientContentError returns content that causes GetContent() to fail
type mockClientContentError struct {
	github.NoopClient
}

func (m *mockClientContentError) GetContents(ctx context.Context, owner, repo, path string, opts *gg.RepositoryContentGetOptions) (fileContent *gg.RepositoryContent, dirContent []*gg.RepositoryContent, err error) {
	return &gg.RepositoryContent{
		Name:     gg.Ptr("invalid.md"),
		Content:  gg.Ptr("invalid-base64!"), // Invalid base64 content
		Encoding: gg.Ptr("base64"),          // This will cause GetContent() to fail when decoding
	}, nil, nil
}

// mockClientNon404Error returns a non-404 error
type mockClientNon404Error struct {
	github.NoopClient
}

func (m *mockClientNon404Error) GetContents(ctx context.Context, owner, repo, path string, opts *gg.RepositoryContentGetOptions) (fileContent *gg.RepositoryContent, dirContent []*gg.RepositoryContent, err error) {
	return nil, nil, &gg.ErrorResponse{
		Response: &http.Response{StatusCode: http.StatusForbidden},
		Message:  "Access denied",
	}
}

// mockClientValidContent returns valid non-empty content
type mockClientValidContent struct {
	github.NoopClient
}

func (m *mockClientValidContent) GetContents(ctx context.Context, owner, repo, path string, opts *gg.RepositoryContentGetOptions) (fileContent *gg.RepositoryContent, dirContent []*gg.RepositoryContent, err error) {
	return &gg.RepositoryContent{
		Name:     gg.Ptr("valid.md"),
		Content:  gg.Ptr("VmFsaWQgY29udGVudA=="), // base64 encoded "Valid content"
		Encoding: gg.Ptr("base64"),
	}, nil, nil
}

func TestCreateOnboardingCommentIfNeededAdditionalCases(t *testing.T) {
	ctx := context.Background()
	jobStore := &mockJobStore{existingJob: false}
	job := &jobs.Job{
		ActorID:           123,
		RepoID:            456,
		OwnerID:           789,
		RepoOwner:         "testowner",
		RepoName:          "testrepo",
		PullRequestNumber: 1,
	}

	t.Run("skip when instructions file exists", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{featureFlagName: true})
		ghClient := &mockClientWithInstructions{}

		comment, err := CreateOnboardingCommentIfNeeded(ctx, ffClient, jobStore, ghClient, job)
		require.NoError(t, err)
		require.Nil(t, comment)
		require.True(t, ghClient.HasNMethodCalls("CreateComment", 0))
	})

	t.Run("skip when instructions directory has files", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{featureFlagName: true})
		ghClient := &mockClientWithInstructionsDir{}

		comment, err := CreateOnboardingCommentIfNeeded(ctx, ffClient, jobStore, ghClient, job)
		require.NoError(t, err)
		require.Nil(t, comment)
		require.True(t, ghClient.HasNMethodCalls("CreateComment", 0))
	})

	t.Run("skip when nested instructions directory has files", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{featureFlagName: true})
		ghClient := &mockClientWithNestedInstructionsDir{}

		comment, err := CreateOnboardingCommentIfNeeded(ctx, ffClient, jobStore, ghClient, job)
		require.NoError(t, err)
		require.Nil(t, comment)
		require.True(t, ghClient.HasNMethodCalls("CreateComment", 0))
	})

	t.Run("error from GetContents call", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{featureFlagName: true})
		ghClient := &mockClientWithError{}

		comment, err := CreateOnboardingCommentIfNeeded(ctx, ffClient, jobStore, ghClient, job)
		require.Error(t, err)
		require.Nil(t, comment)
		require.True(t, ghClient.HasNMethodCalls("CreateComment", 0))
	})

	t.Run("comment creation failure", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{featureFlagName: true})
		ghClient := &mockClientFailComment{}

		comment, err := CreateOnboardingCommentIfNeeded(ctx, ffClient, jobStore, ghClient, job)
		require.Error(t, err)
		require.Nil(t, comment)
		require.True(t, ghClient.HasNMethodCalls("CreateComment", 0))
		require.Contains(t, err.Error(), "failed to create initial comment")
	})
}

func TestFileExistsAndIsNonEmptyEdgeCases(t *testing.T) {
	ctx := context.Background()
	job := &jobs.Job{
		RepoOwner: "testowner",
		RepoName:  "testrepo",
	}

	t.Run("empty file content", func(t *testing.T) {
		ghClient := &mockClientEmptyContent{}

		exists, err := fileExistsAndIsNonEmpty(ctx, ghClient, job, "test-path")
		require.NoError(t, err)
		require.False(t, exists, "empty/whitespace content should return false")
	})

	t.Run("GetContent error", func(t *testing.T) {
		ghClient := &mockClientContentError{}

		exists, err := fileExistsAndIsNonEmpty(ctx, ghClient, job, "test-path")
		require.Error(t, err)
		require.False(t, exists)
	})

	t.Run("non-404 error", func(t *testing.T) {
		ghClient := &mockClientNon404Error{}

		exists, err := fileExistsAndIsNonEmpty(ctx, ghClient, job, "test-path")
		require.Error(t, err)
		require.False(t, exists)
		require.Contains(t, err.Error(), "Access denied")
	})

	t.Run("valid non-empty content", func(t *testing.T) {
		ghClient := &mockClientValidContent{}

		exists, err := fileExistsAndIsNonEmpty(ctx, ghClient, job, "test-path")
		require.NoError(t, err)
		require.True(t, exists)
	})

	t.Run("file not found 404", func(t *testing.T) {
		ghClient := &mockClientForEmpty{}

		exists, err := fileExistsAndIsNonEmpty(ctx, ghClient, job, "test-path")
		require.NoError(t, err)
		require.False(t, exists)
	})
}

// Test instruction file detection behavior through the public API
func TestInstructionFileDetection(t *testing.T) {
	ctx := context.Background()
	jobStore := &mockJobStore{existingJob: false}
	job := &jobs.Job{
		ActorID:           123,
		RepoID:            456,
		OwnerID:           789,
		RepoOwner:         "testowner",
		RepoName:          "testrepo",
		PullRequestNumber: 1,
	}

	t.Run("no onboarding comment when instructions directory has instruction files", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{featureFlagName: true})
		ghClient := &mockClientWithInstructionsDir{}

		// Should not create a comment because instructions exist
		comment, err := CreateOnboardingCommentIfNeeded(ctx, ffClient, jobStore, ghClient, job)
		require.NoError(t, err)
		require.Nil(t, comment)
		require.True(t, ghClient.HasNMethodCalls("CreateComment", 0))
	})

	t.Run("no onboarding comment when nested instructions directory has instruction files", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{featureFlagName: true})
		ghClient := &mockClientWithNestedInstructionsDir{}

		// Should not create a comment because instructions exist
		comment, err := CreateOnboardingCommentIfNeeded(ctx, ffClient, jobStore, ghClient, job)
		require.NoError(t, err)
		require.Nil(t, comment)
		require.True(t, ghClient.HasNMethodCalls("CreateComment", 0))
	})

	t.Run("create onboarding comment when directory has non-instruction files", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{featureFlagName: true})
		ghClient := &mockClientWithNonInstructionFiles{}

		// Should create a comment because no instructions exist
		comment, err := CreateOnboardingCommentIfNeeded(ctx, ffClient, jobStore, ghClient, job)
		require.NoError(t, err)
		require.NotNil(t, comment)
		require.True(t, ghClient.HasNMethodCalls("CreateComment", 1))
	})
}

// mockClientWithNonInstructionFiles returns directory contents with files that don't match the instructions pattern
type mockClientWithNonInstructionFiles struct {
	github.NoopClient
}

func (m *mockClientWithNonInstructionFiles) GetContents(ctx context.Context, owner, repo, path string, opts *gg.RepositoryContentGetOptions) (fileContent *gg.RepositoryContent, dirContent []*gg.RepositoryContent, err error) {
	if path == ".github/instructions" {
		return nil, []*gg.RepositoryContent{
			{
				Name: gg.Ptr("README.md"),
				Type: gg.Ptr("file"),
			},
			{
				Name: gg.Ptr("setup.yaml"),
				Type: gg.Ptr("file"),
			},
		}, nil
	}
	return nil, nil, &gg.ErrorResponse{
		Response: &http.Response{StatusCode: http.StatusNotFound},
	}
}

// mockClientWithManyFiles returns directory contents with many files to test limiting behavior
type mockClientWithManyFiles struct {
	github.NoopClient
	callCount int
}

func (m *mockClientWithManyFiles) GetContents(ctx context.Context, owner, repo, path string, opts *gg.RepositoryContentGetOptions) (fileContent *gg.RepositoryContent, dirContent []*gg.RepositoryContent, err error) {
	m.callCount++

	if path == ".github/instructions" {
		// Return many instruction files to test the limiting behavior
		return nil, []*gg.RepositoryContent{
			{Name: gg.Ptr("file1.instructions.md"), Type: gg.Ptr("file")},
			{Name: gg.Ptr("file2.instructions.md"), Type: gg.Ptr("file")},
			{Name: gg.Ptr("file3.instructions.md"), Type: gg.Ptr("file")},
			{Name: gg.Ptr("file4.instructions.md"), Type: gg.Ptr("file")},
			{Name: gg.Ptr("file5.instructions.md"), Type: gg.Ptr("file")},
			{Name: gg.Ptr("file6.instructions.md"), Type: gg.Ptr("file")},
		}, nil
	}

	// All instruction files return empty content (whitespace only)
	if strings.HasSuffix(path, ".instructions.md") {
		return &gg.RepositoryContent{
			Name:     gg.Ptr("empty.md"),
			Content:  gg.Ptr("ICAgIA=="), // base64 encoded "    " (whitespace only)
			Encoding: gg.Ptr("base64"),
		}, nil, nil
	}

	return nil, nil, &gg.ErrorResponse{
		Response: &http.Response{StatusCode: http.StatusNotFound},
	}
}

// mockClientWithManyDirectories returns nested directories to test directory limiting behavior
type mockClientWithManyDirectories struct {
	github.NoopClient
	callCount int
}

func (m *mockClientWithManyDirectories) GetContents(ctx context.Context, owner, repo, path string, opts *gg.RepositoryContentGetOptions) (fileContent *gg.RepositoryContent, dirContent []*gg.RepositoryContent, err error) {
	m.callCount++

	if path == ".github/instructions" {
		// Return many subdirectories
		return nil, []*gg.RepositoryContent{
			{Name: gg.Ptr("dir1"), Type: gg.Ptr("dir")},
			{Name: gg.Ptr("dir2"), Type: gg.Ptr("dir")},
			{Name: gg.Ptr("dir3"), Type: gg.Ptr("dir")},
			{Name: gg.Ptr("dir4"), Type: gg.Ptr("dir")},
			{Name: gg.Ptr("dir5"), Type: gg.Ptr("dir")},
			{Name: gg.Ptr("dir6"), Type: gg.Ptr("dir")},
		}, nil
	}

	// Each subdirectory returns empty (no instruction files)
	if strings.HasPrefix(path, ".github/instructions/dir") {
		return nil, []*gg.RepositoryContent{}, nil
	}

	return nil, nil, &gg.ErrorResponse{
		Response: &http.Response{StatusCode: http.StatusNotFound},
	}
}

// mockClientWithMixedContent returns a mix of files and directories to test combined limiting
type mockClientWithMixedContent struct {
	github.NoopClient
	callCount int
}

func (m *mockClientWithMixedContent) GetContents(ctx context.Context, owner, repo, path string, opts *gg.RepositoryContentGetOptions) (fileContent *gg.RepositoryContent, dirContent []*gg.RepositoryContent, err error) {
	m.callCount++

	if path == ".github/instructions" {
		// Return mix of files and directories
		return nil, []*gg.RepositoryContent{
			{Name: gg.Ptr("file1.instructions.md"), Type: gg.Ptr("file")},
			{Name: gg.Ptr("dir1"), Type: gg.Ptr("dir")},
			{Name: gg.Ptr("file2.instructions.md"), Type: gg.Ptr("file")},
			{Name: gg.Ptr("dir2"), Type: gg.Ptr("dir")},
			{Name: gg.Ptr("file3.instructions.md"), Type: gg.Ptr("file")},
			{Name: gg.Ptr("dir3"), Type: gg.Ptr("dir")},
		}, nil
	}

	// Instruction files return empty content
	if strings.HasSuffix(path, ".instructions.md") {
		return &gg.RepositoryContent{
			Name:     gg.Ptr("empty.md"),
			Content:  gg.Ptr("ICAgIA=="), // base64 encoded "    " (whitespace only)
			Encoding: gg.Ptr("base64"),
		}, nil, nil
	}

	// Subdirectories return empty
	if strings.HasPrefix(path, ".github/instructions/dir") {
		return nil, []*gg.RepositoryContent{}, nil
	}

	return nil, nil, &gg.ErrorResponse{
		Response: &http.Response{StatusCode: http.StatusNotFound},
	}
}

// mockClientWithValidFirstFile returns valid content for the first instruction file
type mockClientWithValidFirstFile struct {
	github.NoopClient
	callCount int
}

func (m *mockClientWithValidFirstFile) GetContents(ctx context.Context, owner, repo, path string, opts *gg.RepositoryContentGetOptions) (fileContent *gg.RepositoryContent, dirContent []*gg.RepositoryContent, err error) {
	m.callCount++

	if path == ".github/instructions" {
		return nil, []*gg.RepositoryContent{
			{Name: gg.Ptr("file1.instructions.md"), Type: gg.Ptr("file")},
			{Name: gg.Ptr("file2.instructions.md"), Type: gg.Ptr("file")},
			{Name: gg.Ptr("file3.instructions.md"), Type: gg.Ptr("file")},
		}, nil
	}

	if path == ".github/instructions/file1.instructions.md" {
		// Return valid content for first file
		return &gg.RepositoryContent{
			Name:     gg.Ptr("file1.instructions.md"),
			Content:  gg.Ptr("VmFsaWQgY29udGVudA=="), // base64 encoded "Valid content"
			Encoding: gg.Ptr("base64"),
		}, nil, nil
	}

	return nil, nil, &gg.ErrorResponse{
		Response: &http.Response{StatusCode: http.StatusNotFound},
	}
}

func TestFileLimitingBehavior(t *testing.T) {
	ctx := context.Background()
	job := &jobs.Job{
		RepoOwner: "testowner",
		RepoName:  "testrepo",
	}

	t.Run("limits file checks when too many instruction files", func(t *testing.T) {
		ghClient := &mockClientWithManyFiles{}

		hasInstructions, remainingChecks, err := hasInstructionFilesInDirectory(ctx, ghClient, job, ".github/instructions", 5)
		require.NoError(t, err)
		require.False(t, hasInstructions, "should not find instructions since all files are empty")
		require.Equal(t, 0, remainingChecks, "should have exhausted all checks")

		// Should have checked directory + 5 files (the limit should stop further file checks)
		require.Equal(t, 6, ghClient.callCount, "should have made exactly 6 API calls")
	})

	t.Run("limits directory traversal when too many directories", func(t *testing.T) {
		ghClient := &mockClientWithManyDirectories{}

		hasInstructions, remainingChecks, err := hasInstructionFilesInDirectory(ctx, ghClient, job, ".github/instructions", 5)
		require.NoError(t, err)
		require.False(t, hasInstructions, "should not find instructions")
		require.Equal(t, 0, remainingChecks, "should have exhausted all checks")

		// Should have checked main directory + 5 subdirectories
		require.Equal(t, 6, ghClient.callCount, "should have made exactly 6 API calls")
	})

	t.Run("limits combined file and directory checks", func(t *testing.T) {
		ghClient := &mockClientWithMixedContent{}

		hasInstructions, remainingChecks, err := hasInstructionFilesInDirectory(ctx, ghClient, job, ".github/instructions", 5)
		require.NoError(t, err)
		require.False(t, hasInstructions, "should not find instructions")
		require.Equal(t, 0, remainingChecks, "should have exhausted all checks")

		// Should have checked main directory + 5 items (mix of files and directories)
		require.Equal(t, 6, ghClient.callCount, "should have made exactly 6 API calls")
	})

	t.Run("stops early when finding valid instructions", func(t *testing.T) {
		// Custom mock that returns valid content for the first instruction file
		ghClient := &mockClientWithValidFirstFile{}

		hasInstructions, remainingChecks, err := hasInstructionFilesInDirectory(ctx, ghClient, job, ".github/instructions", 5)
		require.NoError(t, err)
		require.True(t, hasInstructions, "should find instructions in first file")
		require.Equal(t, 4, remainingChecks, "should have 4 checks remaining")

		// Should have checked directory + first file only
		require.Equal(t, 2, ghClient.callCount, "should have stopped after finding valid instructions")
	})
}
