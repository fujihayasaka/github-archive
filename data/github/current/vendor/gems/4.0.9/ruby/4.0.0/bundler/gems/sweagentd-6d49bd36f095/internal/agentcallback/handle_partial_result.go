package agentcallback

import (
	"context"
	"encoding/json"
	"net/http"

	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/jobs"
)

type partialResultUpdate struct {
	BranchName string `json:"branchName"`
	Message    string `json:"message"`
}

type partialResult struct {
	PRNumber int `json:"prNumber"`
}

// partialResult is called when the runtime calls the progress_update tool
func (m *jobManager) handlePartialResult(ctx context.Context, r *http.Request, job *jobs.Job, update JobUpdate) (*JobResult, error) {
	m.obsv.LoggerWithRequestTelemetry(ctx, r).Info("processing agent callback: partial result")
	update.publishProgressTelemetry(ctx, m.obsv, job)

	var prp partialResultUpdate
	err := json.Unmarshal([]byte(update.Content), &prp)
	if err != nil {
		return nil, goerrors.Errorf("failed to unmarshal partial result: %w", err)
	}

	// We only want to continually update the PR body if it's the initial
	// job that created the PR. Subsequent jobs on the same PR (e.g.
	// fix-pr-comment) should not overwrite the body with their plan steps.
	// Also skip updating PR description during partial results for non-Copilot-authored PRs.
	if job.HasPullRequest() && !jobs.ShouldSkipMidSessionPRUpdate(ctx, m.ffClient, job) {
		app, err := m.appProvider.FindByID(ctx, job.AgentID)
		if err != nil {
			return nil, goerrors.Errorf("failed to find agentic app by ID: %w", err)
		}
		ghclient, err := m.clients.NewClientForRepo(ctx, app, job)
		if err != nil {
			return nil, goerrors.Errorf("failed to create GitHub client: %w", err)
		}

		repo, err := ghclient.GetRepositoryByID(ctx, job.RepoID)
		if err != nil {
			return nil, goerrors.Errorf("failed to get repository for job: %w", err)
		}

		err = m.updatePullRequest(ctx, ghclient, job, repo, nil, &prp.Message)
		if err != nil {
			return nil, goerrors.Errorf("failed to update pull request: %w", err)
		}
	}

	jobResult := &JobResult{
		Status: jobs.JobStatusRunning,
		Result: &partialResult{
			PRNumber: job.PullRequestNumber,
		},
	}

	return jobResult, nil
}
