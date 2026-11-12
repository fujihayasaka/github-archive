package agentcallback

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"github.com/github/sweagentd/internal/firewall"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/jobs"
)

func (m *jobManager) handleResult(ctx context.Context, r *http.Request, job *jobs.Job, update JobUpdate) (*JobResult, error) {
	switch job.Action {
	case jobs.AgentActionFix:
		return m.handleFixResult(ctx, r, job, update)
	case jobs.AgentActionFixPRComment:
		return m.handleFixPRCommentResult(ctx, r, job, update)
	case jobs.AgentActionTask:
		return m.handleTaskResult(ctx, r, job, update)
	default:
		return nil, &badRequestError{"unknown action: " + string(job.Action)}
	}
}

type fixResultUpdate struct {
	Diff            string                    `json:"diff"`
	BranchName      string                    `json:"branchName"`
	PRTitle         string                    `json:"prTitle"`
	PRDescription   string                    `json:"prDescription"`
	BlockedRequests []firewall.BlockedRequest `json:"blockedRequests"`
}

type fixResult struct {
	PRNumber        int                       `json:"prNumber"`
	BlockedRequests []firewall.BlockedRequest `json:"blockedRequests"`
}

func (m *jobManager) handleFixResult(ctx context.Context, r *http.Request, job *jobs.Job, update JobUpdate) (*JobResult, error) {
	m.obsv.LoggerWithRequestTelemetry(ctx, r).Info("processing agent callback: fix result")
	// TODO (colbylwilliams): shouldn't we publish progress telemetry here too?
	// update.publishProgressTelemetry(ctx, m.obsv, job)

	var frp fixResultUpdate
	err := json.Unmarshal([]byte(update.Content), &frp)
	if err != nil {
		return nil, goerrors.Errorf("failed to unmarshal fix result: %w", err)
	}

	if frp.PRTitle == "" || frp.PRDescription == "" {
		return nil, goerrors.New("PRTitle and PRDescription must both be non-empty")
	}

	title := frp.PRTitle
	body := frp.PRDescription
	if len(frp.BlockedRequests) > 0 {
		// Get GitHub client to fetch repository information
		app, err := m.appProvider.FindByID(job.AgentID)
		if err != nil {
			return nil, goerrors.Errorf("failed to find agentic app by ID: %w", err)
		}
		ghclient, err := m.clients.NewClientForRepo(ctx, app, job)
		if err != nil {
			return nil, goerrors.Errorf("failed to create GitHub client: %w", err)
		}

		// Fetch repository information dynamically
		repo, err := ghclient.GetRepositoryByID(ctx, job.RepoID)
		if err != nil {
			return nil, goerrors.Errorf("failed to get repository for job: %w", err)
		}
		firewallComment, err := firewall.GenerateFirewallComment(frp.BlockedRequests, job, repo.Owner.GetLogin(), repo.GetName())
		if err != nil {
			return nil, goerrors.Errorf("failed to generate firewall comment: %w", err)
		}
		if firewallComment != "" {
			body += "\n\n" + firewallComment
		}
	}

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

		err = m.updatePullRequest(ctx, ghclient, job, repo, &title, &body)
		if err != nil {
			return nil, goerrors.Errorf("failed to update pull request: %w", err)
		}
	}

	jobResult := &JobResult{
		Status:      jobs.JobStatusCompleted, // TS code shows "succeeded" we've codified it as "completed"
		CompletedAt: time.Now().UTC(),
		Result: &fixResult{
			PRNumber:        job.PullRequestNumber,
			BlockedRequests: frp.BlockedRequests,
		},
	}

	m.obsv.LoggerWithRequestTelemetry(ctx, r).
		WithFields(firewall.GenerateFirewallTelemetry(frp.BlockedRequests)...).
		Info("finished processing fix result callback")

	return jobResult, nil
}

func (m *jobManager) handleFixPRCommentResult(ctx context.Context, r *http.Request, job *jobs.Job, update JobUpdate) (*JobResult, error) {
	m.obsv.LoggerWithRequestTelemetry(ctx, r).Info("processing agent callback: fix pr comment result")
	// TODO (colbylwilliams): shouldn't we publish progress telemetry here too?
	// update.publishProgressTelemetry(ctx, m.obsv, job)

	var fp fixResultUpdate
	err := json.Unmarshal([]byte(update.Content), &fp)
	if err != nil {
		return nil, goerrors.Errorf("failed to unmarshal fix pr comment result: %w", err)
	}
	app, err := m.appProvider.FindByID(job.AgentID)
	if err != nil {
		return nil, goerrors.Errorf("failed to find agentic app by ID: %w", err)
	}

	ghclient, err := m.clients.NewClientForRepo(ctx, app, job)
	if err != nil {
		return nil, goerrors.Errorf("failed to create GitHub client: %w", err)
	}

	// Fetch repository information dynamically once for potential use below
	repo, err := ghclient.GetRepositoryByID(ctx, job.RepoID)
	if err != nil {
		return nil, goerrors.Errorf("failed to get repository for job: %w", err)
	}
	repoOwner := repo.Owner.GetLogin()
	repoName := repo.GetName()

	switch {
	case job.ReplyCommentID != 0 && len(fp.BlockedRequests) > 0:
		firewallComment, err := firewall.GenerateFirewallComment(fp.BlockedRequests, job, repoOwner, repoName)
		if err != nil {
			return nil, goerrors.Errorf("failed to generate firewall comment: %w", err)
		}
		if firewallComment != "" {
			comment, err := ghclient.GetComment(ctx, repoOwner, repoName, job.ReplyCommentID)
			if err != nil || comment == nil {
				return nil, goerrors.Errorf("failed to get comment: %w", err)
			}

			body := fmt.Sprintf("%s\n\n%s", comment.GetBody(), firewallComment)
			_, err = ghclient.UpdateComment(ctx, repoOwner, repoName, job.ReplyCommentID, body)
			if err != nil {
				return nil, goerrors.Errorf("failed to update comment: %w", err)
			}
		}
	case len(fp.BlockedRequests) > 0:
		// If there's no comment to update, we need to create one if there's any blocked network traffic
		// TODO: Also update session logs in this case - but we need the details so just a timeline event isn't enough
		firewallComment, err := firewall.GenerateFirewallComment(fp.BlockedRequests, job, repoOwner, repoName)
		if err != nil {
			return nil, goerrors.Errorf("failed to generate firewall comment: %w", err)
		}
		body := fmt.Sprintf("%s\n\n%s", firewall.FirewallStandAloneCommentPrefix, firewallComment)
		_, err = ghclient.CreateComment(ctx, job.RepoID, job.PullRequestNumber, body)
		if err != nil {
			return nil, goerrors.Errorf("failed to create comment: %w", err)
		}
	default:
	}

	if fp.PRTitle != "" || fp.PRDescription != "" {
		err = m.updatePullRequest(ctx, ghclient, job, repo, &fp.PRTitle, &fp.PRDescription)
		if err != nil {
			return nil, goerrors.Errorf("failed to update pull request: %w", err)
		}
	}

	jobResult := &JobResult{
		Status:      jobs.JobStatusCompleted, // TS code shows "succeeded" we've codified it as "completed"
		CompletedAt: time.Now().UTC(),
		Result: &fixResult{
			PRNumber:        job.PullRequestNumber,
			BlockedRequests: fp.BlockedRequests,
		},
	}

	m.obsv.LoggerWithRequestTelemetry(ctx, r).
		WithFields(firewall.GenerateFirewallTelemetry(fp.BlockedRequests)...).
		Info("Job finished. Processing handleFixPRCommentResult callback")

	return jobResult, nil
}

type taskResult struct {
	BlockedRequests []firewall.BlockedRequest `json:"blockedRequests"`
}

// handleTaskResult processes the result of a task action from the agent.
func (m *jobManager) handleTaskResult(ctx context.Context, r *http.Request, _ *jobs.Job, update JobUpdate) (*JobResult, error) {
	m.obsv.LoggerWithRequestTelemetry(ctx, r).Info("processing agent callback: task result")

	var tr taskResult
	err := json.Unmarshal([]byte(update.Content), &tr)
	if err != nil {
		return nil, goerrors.Errorf("failed to unmarshal task result: %w", err)
	}

	jobResult := &JobResult{
		Status:      jobs.JobStatusCompleted,
		CompletedAt: time.Now().UTC(),
		Result: &taskResult{
			BlockedRequests: tr.BlockedRequests,
		},
	}
	m.obsv.LoggerWithRequestTelemetry(ctx, r).
		WithFields(firewall.GenerateFirewallTelemetry(tr.BlockedRequests)...).
		Info("finished processing task result callback")
	return jobResult, nil
}
