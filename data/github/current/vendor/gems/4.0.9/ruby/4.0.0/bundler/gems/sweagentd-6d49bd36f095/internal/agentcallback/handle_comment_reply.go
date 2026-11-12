// Package agentcallback provides handlers for agent callback operations.
package agentcallback

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strings"

	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/jobs"
	db "github.com/github/sweagentd/internal/jobs/store"
	gg "github.com/google/go-github/v75/github"
)

type commentReplyUpdate struct {
	CommentID int64  `json:"comment_id"`
	Message   string `json:"message"`
}

type commentReply struct {
	PRNumber int `json:"prNumber"`
}

func (m *jobManager) handleCommentReply(ctx context.Context, r *http.Request, job *jobs.Job, update JobUpdate) (*JobResult, error) {
	m.obsv.LoggerWithRequestTelemetry(ctx, r).Info("processing agent callback: comment reply")
	update.publishProgressTelemetry(ctx, m.obsv, job)

	var cr commentReplyUpdate
	err := json.Unmarshal([]byte(update.Content), &cr)
	if err != nil {
		return nil, goerrors.Errorf("failed to unmarshal comment reply: %w", err)
	}

	jobResult := &JobResult{
		Status: jobs.JobStatusRunning,
		Result: &commentReply{
			PRNumber: job.PullRequestNumber,
		},
	}

	if cr.CommentID == 0 || cr.Message == "" {
		return jobResult, nil
	}
	app, err := m.appProvider.FindByID(ctx, job.AgentID)
	if err != nil {
		m.obsv.LogAndReportError(ctx, err, "failed to find agentic app by ID")
		return jobResult, nil
	}

	ghclient, err := m.clients.NewClientForRepo(ctx, app, job)
	if err != nil {
		m.obsv.LogAndReportError(ctx, err, "failed to create GitHub client")
		return jobResult, nil
	}

	// Fetch repository information dynamically
	repo, err := ghclient.GetRepositoryByID(ctx, job.RepoID)
	if err != nil {
		m.obsv.LogAndReportError(ctx, err, "failed to get repository for job")
		return jobResult, nil
	}

	actx, err := ghclient.GetPullRequestContext(ctx, job.RepoNodeID, job.PullRequestNumber, m.appProvider.IsAgenticActor)
	if err != nil {
		m.obsv.LogAndReportError(ctx, err, "failed to get pull request context")
		return jobResult, nil
	}

	comment := actx.PullRequest.CommentByID(cr.CommentID)
	if comment != nil {
		err := m.appendComment(ctx, ghclient, job, repo, comment.GetBody(), cr.Message)
		if err != nil {
			m.obsv.LogAndReportError(ctx, err, "failed to append comment")
		}
		err = comment.RemoveReaction(ctx, ghclient, github.GQLReactionContentEyes, m.appProvider.IsAgenticActor)
		if err != nil {
			m.obsv.LogAndReportError(ctx, err, "failed to remove reaction")
		}
		return jobResult, nil
	}

	reviewComment := actx.PullRequest.ReviewCommentByID(cr.CommentID)
	if reviewComment != nil {
		_, err = ghclient.CreateCommentInReplyTo(ctx, repo.Owner.GetLogin(), repo.GetName(), job.PullRequestNumber, cr.Message, cr.CommentID)
		if err != nil {
			m.obsv.LogAndReportError(ctx, err, "failed to append comment in reply")
		}
		err = reviewComment.RemoveReaction(ctx, ghclient, github.GQLReactionContentEyes, m.appProvider.IsAgenticActor)
		if err != nil {
			m.obsv.LogAndReportError(ctx, err, "failed to remove reaction")
		}
		return jobResult, nil
	}

	review := actx.PullRequest.ReviewByID(cr.CommentID)
	if review != nil {
		err := m.appendComment(ctx, ghclient, job, repo, review.GetBody(), cr.Message)
		if err != nil {
			m.obsv.LogAndReportError(ctx, err, "failed to append comment")
		}
		err = review.RemoveReaction(ctx, ghclient, github.GQLReactionContentEyes, m.appProvider.IsAgenticActor)
		if err != nil {
			m.obsv.LogAndReportError(ctx, err, "failed to remove reaction")
		}
		return jobResult, nil
	}

	// We didn't find the comment. Log the error but don't fail the job
	m.obsv.LoggerWithTelemetry(ctx).WithError(goerrors.New("comment not found")).Error("failed to find comment with given ID")

	return jobResult, nil
}

// MaxQuoteLines is the maximum number of lines to include in comment quotes.
const MaxQuoteLines = 3

// MaxQuoteLength is the maximum character length to include in comment quotes.
const MaxQuoteLength = 200

func (m *jobManager) appendComment(ctx context.Context, ghclient github.ClientInterface, job *jobs.Job, repo *gg.Repository, original, message string) error {
	quote := original
	if quote == "" || message == "" {
		return nil
	}

	truncated := false
	if len(quote) > MaxQuoteLength {
		quote = quote[:MaxQuoteLength]
		truncated = true
	}

	// limit the number of lines in the quote
	lines := strings.Split(quote, "\n")
	if len(lines) > MaxQuoteLines {
		lines = lines[:MaxQuoteLines]
		quote = strings.Join(lines, "\n")
		truncated = true
	}

	// add markdown ">" formatting to the quote
	quote = fmt.Sprintf("\n> %s", strings.ReplaceAll(quote, "\n", "\n> "))
	if truncated {
		quote += "..."
	}

	body := fmt.Sprintf("%s\n\n%s", quote, message)

	bodySuffix := job.PullRequestBodySuffix()
	if bodySuffix != "" {
		body = fmt.Sprintf("%s\n\n%s", body, bodySuffix)
	}

	if job.ReplyCommentID == 0 {
		return m.createNewComment(ctx, ghclient, job, repo, body)
	}

	return m.updateExistingComment(ctx, ghclient, job, repo, body)
}

func (m *jobManager) createNewComment(ctx context.Context, ghclient github.ClientInterface, job *jobs.Job, repo *gg.Repository, body string) error {
	reply, err := ghclient.CreateComment(ctx, job.RepoID, job.PullRequestNumber, body)
	if err != nil {
		return goerrors.Errorf("failed to create job reply comment: %w", err)
	}

	err = m.jobsStore.PatchJob(ctx, job, db.JobPatch{ReplyCommentID: reply.ID})
	if err == nil {
		return nil
	}
	if !errors.Is(err, db.ErrPreconditionFailedOnUpdate) {
		return goerrors.Errorf("failed to update job reply_comment_id: %w", err)
	}

	// ErrPreconditionFailedOnUpdate error means another process updated the job
	// before us. This is almost certainly caused by the agent using parallel tool
	// calls (reply_to_comment) to reply to multiple comments simultaneously.
	//
	// Since another callback beat us to creating the new comment and updating
	// the job's ReplyCommentID, we'll need to delete the comment we just created,
	// re-fetch the job to get the updated ReplyCommentID, and then append our
	// message to the existing comment.
	err = ghclient.DeleteComment(ctx, job.RepoID, reply.GetID())
	if err != nil {
		return goerrors.Errorf("failed to delete stale job reply comment: %w", err)
	}
	updatedJob, err := m.jobsStore.GetJob(ctx, job.OwnerID, job.RepoID, job.ID)
	if err != nil {
		return goerrors.Errorf("failed to get updated job after precondition failed: %w", err)
	}
	if updatedJob.ReplyCommentID == 0 {
		return goerrors.New("job reply comment ID is still zero after precondition failed")
	}

	return m.updateExistingComment(ctx, ghclient, updatedJob, repo, body)
}

func (m *jobManager) updateExistingComment(ctx context.Context, ghclient github.ClientInterface, job *jobs.Job, repo *gg.Repository, body string) error {
	repoOwner := repo.Owner.GetLogin()
	repoName := repo.GetName()

	reply, err := ghclient.GetComment(ctx, repoOwner, repoName, job.ReplyCommentID)
	if err != nil {
		return goerrors.Errorf("failed to get job reply comment: %w", err)
	}
	if reply == nil {
		return goerrors.New("job reply comment not found")
	}

	body = fmt.Sprintf("%s\n\n%s", reply.GetBody(), body)

	_, err = ghclient.UpdateComment(ctx, repoOwner, repoName, job.ReplyCommentID, body)
	if err != nil {
		return goerrors.Errorf("failed to update comment: %w", err)
	}
	return nil
}
