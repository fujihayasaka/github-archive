package agent

import (
	"context"
	"strings"
	"testing"

	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobs/progress"
	db "github.com/github/sweagentd/internal/jobs/store"
	"github.com/github/sweagentd/internal/jobservice"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/tips"
	gg "github.com/google/go-github/v75/github"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestExtractCoreBodyAndSuffix(t *testing.T) {
	suffixSep := jobservice.PullRequestBodySuffixSeparator
	tipSep := tips.PullRequestBodyTipSeparator
	originalSep := jobservice.PullRequestBodyOriginalPromptSeparator

	t.Run("body only", func(t *testing.T) {
		core, suffix, tip := extractCoreBodyAndSuffix("Just a body")
		assert.Equal(t, "Just a body", core)
		assert.Empty(t, suffix)
		assert.Empty(t, tip)
	})

	t.Run("body with suffix", func(t *testing.T) {
		body := "Core body" + suffixSep + "Suffix content"
		core, suffix, tip := extractCoreBodyAndSuffix(body)
		assert.Equal(t, "Core body", core)
		assert.Equal(t, suffixSep+"Suffix content", suffix)
		assert.Empty(t, tip)
	})

	t.Run("body with tip", func(t *testing.T) {
		body := "Core body" + tipSep + "Tip content"
		core, suffix, tip := extractCoreBodyAndSuffix(body)
		assert.Equal(t, "Core body", core)
		assert.Empty(t, suffix)
		assert.Equal(t, tipSep+"Tip content", tip)
	})

	t.Run("body with suffix and tip", func(t *testing.T) {
		body := "Core body" + suffixSep + "Suffix content" + tipSep + "Tip content"
		core, suffix, tip := extractCoreBodyAndSuffix(body)
		assert.Equal(t, "Core body", core)
		assert.Equal(t, suffixSep+"Suffix content", suffix)
		assert.Equal(t, tipSep+"Tip content", tip)
	})

	t.Run("body with original prompt separator", func(t *testing.T) {
		body := "Core body" + originalSep + "Original prompt"
		core, suffix, tip := extractCoreBodyAndSuffix(body)
		assert.Equal(t, "Core body", core)
		assert.Equal(t, originalSep+"Original prompt", suffix)
		assert.Empty(t, tip)
	})

	t.Run("empty body", func(t *testing.T) {
		core, suffix, tip := extractCoreBodyAndSuffix("")
		assert.Empty(t, core)
		assert.Empty(t, suffix)
		assert.Empty(t, tip)
	})
}

func TestDetermineSuffix(t *testing.T) {
	suffixSep := jobservice.PullRequestBodySuffixSeparator

	t.Run("job has suffix with separator", func(t *testing.T) {
		job := &jobs.Job{
			Features: jobs.EnvironmentFeatures{
				PullRequest: &jobs.PullRequestFeature{
					BodySuffix: suffixSep + "Job suffix",
				},
			},
		}
		result := determineSuffix(job, "")
		assert.Equal(t, suffixSep+"Job suffix", result)
	})

	t.Run("job has suffix without separator", func(t *testing.T) {
		job := &jobs.Job{
			Features: jobs.EnvironmentFeatures{
				PullRequest: &jobs.PullRequestFeature{
					BodySuffix: "Plain suffix",
				},
			},
		}
		result := determineSuffix(job, "")
		assert.Equal(t, suffixSep+"Plain suffix", result)
	})

	t.Run("no job suffix preserves current", func(t *testing.T) {
		job := &jobs.Job{}
		current := suffixSep + "Existing suffix"
		result := determineSuffix(job, current)
		assert.Equal(t, current, result)
	})

	t.Run("no suffix at all", func(t *testing.T) {
		job := &jobs.Job{}
		result := determineSuffix(job, "")
		assert.Empty(t, result)
	})
}

// stubStore implements the store interface needed by Service for testing.
type stubStore struct {
	patchJobCalled bool
	patchJobErr    error
}

func (s *stubStore) GetJob(context.Context, int64, int64, string) (*jobs.Job, error) {
	return nil, nil
}

func (s *stubStore) GetJobSummariesForAssignmentID(context.Context, int64, int64, string) ([]*jobs.JobSummary, error) {
	return nil, nil
}

func (s *stubStore) PatchJob(_ context.Context, _ *jobs.Job, _ db.JobPatch, _ ...db.PatchJobOption) error {
	s.patchJobCalled = true
	return s.patchJobErr
}

func (s *stubStore) CreateProgress(_ context.Context, p *progress.Progress) (*progress.Progress, error) {
	return p, nil
}

func (s *stubStore) BatchCreateProgress(_ context.Context, ps []*progress.Progress) ([]*progress.Progress, error) {
	return ps, nil
}

func (s *stubStore) ListProgress(context.Context, string, string) ([]*progress.Progress, error) {
	return nil, nil
}

func (s *stubStore) ListProgressByNamespace(context.Context, string, string, []string) ([]*progress.Progress, error) {
	return nil, nil
}

func newTestService(t *testing.T, cf github.ClientFactoryInterface, store *stubStore) *Service {
	t.Helper()
	obsv := observability.NewNoopExporters()
	appProvider := agenticapptest.NewTestProvider(t)
	return &Service{
		store:       store,
		cpf:         cf,
		obsv:        obsv,
		appProvider: appProvider,
	}
}

func TestUpdateJobPullRequestMidSession(t *testing.T) {
	t.Run("skips when job has no PR", func(t *testing.T) {
		svc := newTestService(t, &github.NoopClientFactory{}, &stubStore{})
		job := &jobs.Job{ID: "1-2-uuid"}
		err := svc.UpdateJobPullRequestMidSession(context.Background(), job, ReportProgressContent{
			PRTitle: "New title",
		})
		require.NoError(t, err)
	})

	t.Run("updates title when different", func(t *testing.T) {
		cf := &github.NoopClientFactory{
			MockPullRequest: &gg.PullRequest{
				ID:     gg.Ptr(int64(1)),
				Number: gg.Ptr(42),
				Title:  gg.Ptr("Old title"),
				Body:   gg.Ptr("Body"),
			},
		}
		svc := newTestService(t, cf, &stubStore{})
		job := &jobs.Job{
			ID:                "1-2-uuid",
			PullRequestID:     100,
			PullRequestNumber: 42,
			RepoID:            2,
		}
		err := svc.UpdateJobPullRequestMidSession(context.Background(), job, ReportProgressContent{
			PRTitle: "New title",
		})
		require.NoError(t, err)
	})

	t.Run("skips update when title unchanged", func(t *testing.T) {
		cf := &github.NoopClientFactory{
			MockPullRequest: &gg.PullRequest{
				ID:     gg.Ptr(int64(1)),
				Number: gg.Ptr(42),
				Title:  gg.Ptr("Same title"),
				Body:   gg.Ptr("Body"),
			},
		}
		svc := newTestService(t, cf, &stubStore{})
		job := &jobs.Job{
			ID:                "1-2-uuid",
			PullRequestID:     100,
			PullRequestNumber: 42,
			RepoID:            2,
		}
		err := svc.UpdateJobPullRequestMidSession(context.Background(), job, ReportProgressContent{
			PRTitle: "Same title",
		})
		require.NoError(t, err)
	})

	t.Run("truncates long title", func(t *testing.T) {
		longTitle := strings.Repeat("a", 300)
		cf := &github.NoopClientFactory{
			MockPullRequest: &gg.PullRequest{
				ID:     gg.Ptr(int64(1)),
				Number: gg.Ptr(42),
				Title:  gg.Ptr("Old title"),
				Body:   gg.Ptr("Body"),
			},
		}
		svc := newTestService(t, cf, &stubStore{})
		job := &jobs.Job{
			ID:                "1-2-uuid",
			PullRequestID:     100,
			PullRequestNumber: 42,
			RepoID:            2,
		}
		err := svc.UpdateJobPullRequestMidSession(context.Background(), job, ReportProgressContent{
			PRTitle: longTitle,
		})
		require.NoError(t, err)
	})

	t.Run("updates body with suffix preservation", func(t *testing.T) {
		suffixSep := jobservice.PullRequestBodySuffixSeparator
		existingBody := "Old core" + suffixSep + "Suffix"
		cf := &github.NoopClientFactory{
			MockPullRequest: &gg.PullRequest{
				ID:     gg.Ptr(int64(1)),
				Number: gg.Ptr(42),
				Title:  gg.Ptr("Title"),
				Body:   gg.Ptr(existingBody),
			},
		}
		svc := newTestService(t, cf, &stubStore{})
		job := &jobs.Job{
			ID:                "1-2-uuid",
			PullRequestID:     100,
			PullRequestNumber: 42,
			RepoID:            2,
		}
		err := svc.UpdateJobPullRequestMidSession(context.Background(), job, ReportProgressContent{
			PRDescription: "New core body",
		})
		require.NoError(t, err)
	})

	t.Run("skips when empty content", func(t *testing.T) {
		cf := &github.NoopClientFactory{
			MockPullRequest: &gg.PullRequest{
				ID:     gg.Ptr(int64(1)),
				Number: gg.Ptr(42),
				Title:  gg.Ptr("Title"),
				Body:   gg.Ptr("Body"),
			},
		}
		svc := newTestService(t, cf, &stubStore{})
		job := &jobs.Job{
			ID:                "1-2-uuid",
			PullRequestID:     100,
			PullRequestNumber: 42,
			RepoID:            2,
		}
		err := svc.UpdateJobPullRequestMidSession(context.Background(), job, ReportProgressContent{})
		require.NoError(t, err)
	})

	t.Run("skips fix_failed_workflow when flag enabled", func(t *testing.T) {
		trackedClient := &github.NoopClient{
			MockPullRequest: &gg.PullRequest{
				ID:     gg.Ptr(int64(1)),
				Number: gg.Ptr(42),
				Title:  gg.Ptr("Old title"),
				Body:   gg.Ptr("Old body"),
				User:   &gg.User{Login: gg.Ptr("copilot-swe-agent[bot]")},
			},
		}
		cf := &github.NoopClientFactory{
			MockNewClientFromRepo: func(_ context.Context, _, _ int64) (github.ClientInterface, error) {
				return trackedClient, nil
			},
		}
		svc := newTestService(t, cf, &stubStore{})
		svc.ff = featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentSkipPRUpdatesForFixFailedWorkflowJobs: true,
		})
		job := &jobs.Job{
			ID:                "1-2-uuid",
			PullRequestID:     100,
			PullRequestNumber: 42,
			RepoID:            2,
			EventType:         jobs.EventTypeFixFailedWorkflow,
		}
		err := svc.UpdateJobPullRequestMidSession(context.Background(), job, ReportProgressContent{
			PRTitle:       "New title",
			PRDescription: "New body",
		})
		require.NoError(t, err)
		require.False(t, trackedClient.HasMethodCall("GetPullRequest"),
			"GetPullRequest should not be called when skip flag is enabled for fix_failed_workflow")
		require.False(t, trackedClient.HasMethodCall("UpdatePullRequest"),
			"UpdatePullRequest should not be called when skip flag is enabled for fix_failed_workflow")
	})

	t.Run("skips code_review_fix_with_copilot when flag enabled", func(t *testing.T) {
		trackedClient := &github.NoopClient{
			MockPullRequest: &gg.PullRequest{
				ID:     gg.Ptr(int64(1)),
				Number: gg.Ptr(42),
				Title:  gg.Ptr("Old title"),
				Body:   gg.Ptr("Old body"),
				User:   &gg.User{Login: gg.Ptr("copilot-swe-agent[bot]")},
			},
		}
		cf := &github.NoopClientFactory{
			MockNewClientFromRepo: func(_ context.Context, _, _ int64) (github.ClientInterface, error) {
				return trackedClient, nil
			},
		}
		svc := newTestService(t, cf, &stubStore{})
		svc.ff = featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentSkipPRUpdatesForCodeReviewFixJobs: true,
		})
		job := &jobs.Job{
			ID:                "1-2-uuid",
			PullRequestID:     100,
			PullRequestNumber: 42,
			RepoID:            2,
			EventType:         jobs.EventTypeCodeReviewFixWithCopilot,
		}
		err := svc.UpdateJobPullRequestMidSession(context.Background(), job, ReportProgressContent{
			PRTitle:       "New title",
			PRDescription: "New body",
		})
		require.NoError(t, err)
		require.False(t, trackedClient.HasMethodCall("GetPullRequest"),
			"GetPullRequest should not be called when skip flag is enabled for code_review_fix_with_copilot")
		require.False(t, trackedClient.HasMethodCall("UpdatePullRequest"),
			"UpdatePullRequest should not be called when skip flag is enabled for code_review_fix_with_copilot")
	})

	t.Run("updates fix_failed_workflow when flag disabled", func(t *testing.T) {
		trackedClient := &github.NoopClient{
			MockPullRequest: &gg.PullRequest{
				ID:     gg.Ptr(int64(1)),
				Number: gg.Ptr(42),
				Title:  gg.Ptr("Old title"),
				Body:   gg.Ptr("Old body"),
				User:   &gg.User{Login: gg.Ptr("copilot-swe-agent[bot]")},
			},
		}
		cf := &github.NoopClientFactory{
			MockNewClientFromRepo: func(_ context.Context, _, _ int64) (github.ClientInterface, error) {
				return trackedClient, nil
			},
		}
		svc := newTestService(t, cf, &stubStore{})
		svc.ff = featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentSkipPRUpdatesForFixFailedWorkflowJobs: false,
		})
		job := &jobs.Job{
			ID:                "1-2-uuid",
			PullRequestID:     100,
			PullRequestNumber: 42,
			RepoID:            2,
			EventType:         jobs.EventTypeFixFailedWorkflow,
		}
		err := svc.UpdateJobPullRequestMidSession(context.Background(), job, ReportProgressContent{
			PRTitle: "New title",
		})
		require.NoError(t, err)
		require.True(t, trackedClient.HasMethodCall("UpdatePullRequest"),
			"UpdatePullRequest should be called when skip flag is disabled")
	})
}

func TestReplyToJobComment(t *testing.T) {
	t.Run("skips when comment ID is zero", func(t *testing.T) {
		svc := newTestService(t, &github.NoopClientFactory{}, &stubStore{})
		job := &jobs.Job{
			ID:                "1-2-uuid",
			PullRequestID:     100,
			PullRequestNumber: 42,
		}
		err := svc.ReplyToJobComment(context.Background(), job, CommentReplyContent{
			CommentID: 0,
			Message:   "test",
		})
		require.NoError(t, err)
	})

	t.Run("skips when message is empty", func(t *testing.T) {
		svc := newTestService(t, &github.NoopClientFactory{}, &stubStore{})
		job := &jobs.Job{
			ID:                "1-2-uuid",
			PullRequestID:     100,
			PullRequestNumber: 42,
		}
		err := svc.ReplyToJobComment(context.Background(), job, CommentReplyContent{
			CommentID: 42,
			Message:   "",
		})
		require.NoError(t, err)
	})

	t.Run("skips when job has no PR", func(t *testing.T) {
		svc := newTestService(t, &github.NoopClientFactory{}, &stubStore{})
		job := &jobs.Job{ID: "1-2-uuid"}
		err := svc.ReplyToJobComment(context.Background(), job, CommentReplyContent{
			CommentID: 42,
			Message:   "Done!",
		})
		require.NoError(t, err)
	})
}
