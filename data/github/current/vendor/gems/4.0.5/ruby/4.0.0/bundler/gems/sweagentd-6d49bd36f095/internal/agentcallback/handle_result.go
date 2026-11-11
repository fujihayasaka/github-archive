package agentcallback

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/sweagentd/internal/capi"
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

	// Store PR metadata on the job so the Hydro JobUpdated event includes GeneratedPullData
	job.PullRequestTitle = frp.PRTitle
	job.PullRequestDescription = frp.PRDescription

	m.storeGeneratedPullData(ctx, r, job, frp.PRTitle, frp.PRDescription)

	title := frp.PRTitle
	body := frp.PRDescription
	if len(frp.BlockedRequests) > 0 {
		// Get GitHub client to fetch repository information
		app, err := m.appProvider.FindByID(ctx, job.AgentID)
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
		firewallComment, err := firewall.GenerateFirewallComment(frp.BlockedRequests, job, repo.GetHTMLURL())
		if err != nil {
			return nil, goerrors.Errorf("failed to generate firewall comment: %w", err)
		}
		if firewallComment != "" {
			body += "\n\n" + firewallComment
		}
	}

	if job.HasPullRequest() && !jobs.ShouldSkipPostSessionPRUpdate(ctx, m.ffClient, job) {
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
	app, err := m.appProvider.FindByID(ctx, job.AgentID)
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
		firewallComment, err := firewall.GenerateFirewallComment(fp.BlockedRequests, job, repo.GetHTMLURL())
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
		firewallComment, err := firewall.GenerateFirewallComment(fp.BlockedRequests, job, repo.GetHTMLURL())
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

	if (fp.PRTitle != "" || fp.PRDescription != "") && !jobs.ShouldSkipPostSessionPRUpdate(ctx, m.ffClient, job) {
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
	PRTitle         string                    `json:"prTitle"`
	PRDescription   string                    `json:"prDescription"`
	BlockedRequests []firewall.BlockedRequest `json:"blockedRequests"`
}

// handleTaskResult processes the result of a task action from the agent.
func (m *jobManager) handleTaskResult(ctx context.Context, r *http.Request, job *jobs.Job, update JobUpdate) (*JobResult, error) {
	m.obsv.LoggerWithRequestTelemetry(ctx, r).Info("processing agent callback: task result")

	var tr taskResult
	err := json.Unmarshal([]byte(update.Content), &tr)
	if err != nil {
		return nil, goerrors.Errorf("failed to unmarshal task result: %w", err)
	}

	m.obsv.LoggerWithRequestTelemetry(ctx, r).
		WithFields(kvp.String("pr_title", tr.PRTitle), kvp.Int("pr_description_length", len(tr.PRDescription)), kvp.Bool("use_async_sessions", job.UseAsyncSessions)).
		Info("task result: received PR title and description")

	job.PullRequestTitle = tr.PRTitle
	job.PullRequestDescription = tr.PRDescription

	m.storeGeneratedPullData(ctx, r, job, tr.PRTitle, tr.PRDescription)

	jobResult := &JobResult{
		Status:      jobs.JobStatusCompleted,
		CompletedAt: time.Now().UTC(),
		Result: &taskResult{
			PRTitle:         tr.PRTitle,
			PRDescription:   tr.PRDescription,
			BlockedRequests: tr.BlockedRequests,
		},
	}
	m.obsv.LoggerWithRequestTelemetry(ctx, r).
		WithFields(firewall.GenerateFirewallTelemetry(tr.BlockedRequests)...).
		Info("finished processing task result callback")
	return jobResult, nil
}

// storeGeneratedPullData persists agent-generated PR metadata so the deferred
// PR creation flow in mission-control can use it.
func (m *jobManager) storeGeneratedPullData(ctx context.Context, r *http.Request, job *jobs.Job, prTitle, prDescription string) {
	if job.UseAsyncSessions || (prTitle == "" && prDescription == "") {
		return
	}

	sessionUpdate := capi.SessionUpdate{
		GeneratedPullData: &capi.GeneratedPullData{
			Title:       prTitle,
			Description: prDescription,
		},
	}
	err := m.jobService.UpdateSession(ctx, job, sessionUpdate)
	if err != nil {
		m.obsv.LoggerWithRequestTelemetry(ctx, r).WithError(err).Warn("failed to update session with PR title/description")
	}
}
