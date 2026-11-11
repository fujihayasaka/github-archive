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

	// We now only want to continually update the PR if it's the initial
	// job and we're updating the body of the PR itself. This should only
	// happen if the job has a PR associated with it.
	if job.HasPullRequest() {
		app, err := m.appProvider.FindByID(job.AgentID)
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
