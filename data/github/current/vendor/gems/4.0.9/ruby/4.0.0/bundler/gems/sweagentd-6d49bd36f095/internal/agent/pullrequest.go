package agent

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/jobs"
	db "github.com/github/sweagentd/internal/jobs/store"
	jobservice "github.com/github/sweagentd/internal/jobservice"
	"github.com/github/sweagentd/internal/tips"
	gg "github.com/google/go-github/v75/github"
)

// ReportProgressContent is the expected content shape for kind="report_progress" events.
type ReportProgressContent struct {
	PRTitle       string `json:"pr_title"`
	PRDescription string `json:"pr_description"`
}

// CommentReplyContent is the expected content shape for kind="comment_reply" events.
type CommentReplyContent struct {
	CommentID int64  `json:"comment_id"`
	Message   string `json:"message"`
}

// UpdateJobPullRequestMidSession updates the PR title and/or description for a job.
// It fetches the current PR, intelligently merges body sections (preserving
// auto-generated suffixes and tips), and only issues an update if content changed.
func (s *Service) UpdateJobPullRequestMidSession(ctx context.Context, job *jobs.Job, content ReportProgressContent) error {
	if !job.HasPullRequest() {
		return nil
	}

	if jobs.ShouldSkipMidSessionPRUpdate(ctx, s.ff, job) {
		s.obsv.LoggerWithTelemetry(ctx).Debug(fmt.Sprintf("skipping mid-session PR update (repo_id=%d, pr_number=%d, event_type=%s, action=%s)", job.RepoID, job.PullRequestNumber, job.EventType, job.Action))
		return nil
	}

	return s.updateJobPullRequest(ctx, job, content)
}

// UpdateJobPullRequestPostSession updates the final PR title and/or description for a job.
// It uses post-session skip semantics to match legacy final-result callback behavior.
func (s *Service) UpdateJobPullRequestPostSession(ctx context.Context, job *jobs.Job, content ReportProgressContent) error {
	if !job.HasPullRequest() {
		return nil
	}

	if jobs.ShouldSkipPostSessionPRUpdate(ctx, s.ff, job) {
		s.obsv.LoggerWithTelemetry(ctx).Debug(fmt.Sprintf("skipping post-session PR update (repo_id=%d, pr_number=%d, event_type=%s, action=%s)", job.RepoID, job.PullRequestNumber, job.EventType, job.Action))
		return nil
	}

	return s.updateJobPullRequest(ctx, job, content)
}

func (s *Service) updateJobPullRequest(ctx context.Context, job *jobs.Job, content ReportProgressContent) error {
	app, err := s.appProvider.FindByID(ctx, job.AgentID)
	if err != nil {
		return goerrors.Errorf("failed to find app for PR update: %w", err)
	}

	ghclient, err := s.cpf.NewClientForRepo(ctx, app, job)
	if err != nil {
		return goerrors.Errorf("failed to create GitHub client for PR update: %w", err)
	}

	pr, err := ghclient.GetPullRequest(ctx, job.RepoID, job.PullRequestNumber)
	if err != nil {
		return goerrors.Errorf("failed to get pull request: %w", err)
	}

	needsUpdate := false

	// Handle title update
	if content.PRTitle != "" {
		newTitle := strings.TrimSpace(content.PRTitle)
		if newTitle != "" {
			if len(newTitle) > github.MaxPullRequestTitleLength {
				newTitle = truncateUTF8(newTitle, github.MaxPullRequestTitleLength-3) + "..."
			}
			if newTitle != pr.GetTitle() {
				pr.Title = &newTitle
				needsUpdate = true
			}
		}
	}

	// Handle body/description update
	if content.PRDescription != "" {
		newCoreBody := strings.TrimSpace(content.PRDescription)
		if newCoreBody != "" {
			newBody, bodyChanged := s.processBodyUpdate(ctx, job, pr.GetBody(), newCoreBody)
			if bodyChanged {
				pr.Body = &newBody
				needsUpdate = true
			}
		}
	}

	if needsUpdate {
		_, err = ghclient.UpdatePullRequest(ctx, job.RepoID, pr)
		return err
	}

	return nil
}

// processBodyUpdate processes the body update logic and returns the new body and whether it changed.
func (s *Service) processBodyUpdate(ctx context.Context, job *jobs.Job, currentPRBody, newCoreBody string) (string, bool) {
	currentCoreBody, currentSuffix, currentTip := extractCoreBodyAndSuffix(currentPRBody)

	newBody := newCoreBody

	// Add suffix
	suffixToAdd := determineSuffix(job, currentSuffix)
	if suffixToAdd != "" {
		newBody += suffixToAdd
	}

	// Add tip (only for Copilot apps)
	tipToAdd := s.determineTip(ctx, job, currentTip)
	if tipToAdd != "" {
		newBody += tipToAdd
	}

	return newBody, currentCoreBody != newCoreBody
}

// determineSuffix determines what suffix should be added to the body.
func determineSuffix(job *jobs.Job, currentSuffix string) string {
	bodySuffix := job.PullRequestBodySuffix()
	if bodySuffix != "" {
		if strings.Contains(bodySuffix, jobservice.PullRequestBodySuffixSeparator) {
			return bodySuffix
		}
		return jobservice.PullRequestBodySuffixSeparator + bodySuffix
	}
	return currentSuffix
}

// determineTip determines what tip should be added to the body.
func (s *Service) determineTip(_ context.Context, _ *jobs.Job, currentTip string) string {
	// Preserve existing tips; skip generating new ones since we don't have
	// the full repository context needed by GetRandomTipForJob.
	return currentTip
}

// extractCoreBodyAndSuffix extracts the core body, suffix, and tip from a pull request body.
func extractCoreBodyAndSuffix(prBody string) (core, suffix, tip string) {
	originalPromptIndex := strings.Index(prBody, jobservice.PullRequestBodyOriginalPromptSeparator)
	suffixIndex := strings.Index(prBody, jobservice.PullRequestBodySuffixSeparator)
	tipIndex := strings.Index(prBody, tips.PullRequestBodyTipSeparator)

	// Find where suffix content starts (whichever separator comes first)
	suffixContentStart := -1
	if originalPromptIndex != -1 && (suffixIndex == -1 || originalPromptIndex < suffixIndex) {
		suffixContentStart = originalPromptIndex
	} else if suffixIndex != -1 {
		suffixContentStart = suffixIndex
	}

	switch {
	case suffixContentStart != -1 && tipIndex != -1 && suffixContentStart < tipIndex:
		core = prBody[:suffixContentStart]
		suffix = prBody[suffixContentStart:tipIndex]
		tip = prBody[tipIndex:]
	case suffixContentStart != -1 && tipIndex != -1 && tipIndex < suffixContentStart:
		core = prBody[:tipIndex]
		tip = prBody[tipIndex:suffixContentStart]
		suffix = prBody[suffixContentStart:]
	case suffixContentStart != -1:
		core = prBody[:suffixContentStart]
		suffix = prBody[suffixContentStart:]
	case tipIndex != -1:
		core = prBody[:tipIndex]
		tip = prBody[tipIndex:]
	default:
		core = prBody
	}

	return core, suffix, tip
}

// maxQuoteLines is the maximum number of lines to include in comment quotes.
const maxQuoteLines = 3

// maxQuoteLength is the maximum character length to include in comment quotes.
const maxQuoteLength = 200

// ReplyToJobComment posts a reply to a PR comment for a job.
// It finds the original comment (issue comment, review comment, or review),
// appends the agent's reply with a truncated quote, and removes the 👀 reaction.
func (s *Service) ReplyToJobComment(ctx context.Context, job *jobs.Job, content CommentReplyContent) error {
	if content.CommentID == 0 || content.Message == "" {
		return nil
	}

	if !job.HasPullRequest() {
		return nil
	}

	app, err := s.appProvider.FindByID(ctx, job.AgentID)
	if err != nil {
		return goerrors.Errorf("failed to find app for comment reply: %w", err)
	}

	ghclient, err := s.cpf.NewClientForRepo(ctx, app, job)
	if err != nil {
		return goerrors.Errorf("failed to create GitHub client for comment reply: %w", err)
	}

	repo, err := ghclient.GetRepositoryByID(ctx, job.RepoID)
	if err != nil {
		return goerrors.Errorf("failed to get repository for comment reply: %w", err)
	}

	actx, err := ghclient.GetPullRequestContext(ctx, job.RepoNodeID, job.PullRequestNumber, s.appProvider.IsAgenticActor)
	if err != nil {
		return goerrors.Errorf("failed to get pull request context: %w", err)
	}

	// Try issue comment first
	comment := actx.PullRequest.CommentByID(content.CommentID)
	if comment != nil {
		err := s.appendComment(ctx, ghclient, job, repo, comment.GetBody(), content.Message)
		if err != nil {
			return err
		}
		_ = comment.RemoveReaction(ctx, ghclient, github.GQLReactionContentEyes, s.appProvider.IsAgenticActor)
		return nil
	}

	// Try review comment
	reviewComment := actx.PullRequest.ReviewCommentByID(content.CommentID)
	if reviewComment != nil {
		_, err = ghclient.CreateCommentInReplyTo(ctx, repo.Owner.GetLogin(), repo.GetName(), job.PullRequestNumber, content.Message, content.CommentID)
		if err != nil {
			return goerrors.Errorf("failed to create reply to review comment: %w", err)
		}
		_ = reviewComment.RemoveReaction(ctx, ghclient, github.GQLReactionContentEyes, s.appProvider.IsAgenticActor)
		return nil
	}

	// Try review
	review := actx.PullRequest.ReviewByID(content.CommentID)
	if review != nil {
		err := s.appendComment(ctx, ghclient, job, repo, review.GetBody(), content.Message)
		if err != nil {
			return err
		}
		_ = review.RemoveReaction(ctx, ghclient, github.GQLReactionContentEyes, s.appProvider.IsAgenticActor)
		return nil
	}

	s.obsv.LoggerWithTelemetry(ctx).Error("comment not found for reply, comment_id: " + fmt.Sprintf("%d", content.CommentID))
	return nil
}

func (s *Service) appendComment(ctx context.Context, ghclient github.ClientInterface, job *jobs.Job, repo *gg.Repository, original, message string) error {
	if message == "" {
		return nil
	}

	var body string
	if original != "" {
		quote := original
		truncated := false
		if len(quote) > maxQuoteLength {
			quote = quote[:maxQuoteLength]
			truncated = true
		}

		lines := strings.Split(quote, "\n")
		if len(lines) > maxQuoteLines {
			lines = lines[:maxQuoteLines]
			quote = strings.Join(lines, "\n")
			truncated = true
		}

		quote = fmt.Sprintf("\n> %s", strings.ReplaceAll(quote, "\n", "\n> "))
		if truncated {
			quote += "..."
		}

		body = fmt.Sprintf("%s\n\n%s", quote, message)
	} else {
		body = message
	}

	bodySuffix := job.PullRequestBodySuffix()
	if bodySuffix != "" {
		body = fmt.Sprintf("%s\n\n%s", body, bodySuffix)
	}

	if job.ReplyCommentID == 0 {
		return s.createNewComment(ctx, ghclient, job, repo, body)
	}

	return s.updateExistingComment(ctx, ghclient, job, repo, body)
}

func (s *Service) createNewComment(ctx context.Context, ghclient github.ClientInterface, job *jobs.Job, repo *gg.Repository, body string) error {
	reply, err := ghclient.CreateComment(ctx, job.RepoID, job.PullRequestNumber, body)
	if err != nil {
		return goerrors.Errorf("failed to create job reply comment: %w", err)
	}

	err = s.store.PatchJob(ctx, job, db.JobPatch{ReplyCommentID: reply.ID})
	if err == nil {
		return nil
	}
	if !errors.Is(err, db.ErrPreconditionFailedOnUpdate) {
		return goerrors.Errorf("failed to update job reply_comment_id: %w", err)
	}

	// Another process updated the job first (parallel tool calls).
	// Delete our comment and append to the existing one.
	err = ghclient.DeleteComment(ctx, job.RepoID, reply.GetID())
	if err != nil {
		return goerrors.Errorf("failed to delete stale job reply comment: %w", err)
	}
	updatedJob, err := s.store.GetJob(ctx, job.OwnerID, job.RepoID, job.ID)
	if err != nil {
		return goerrors.Errorf("failed to get updated job after precondition failed: %w", err)
	}
	if updatedJob.ReplyCommentID == 0 {
		return goerrors.New("job reply comment ID is still zero after precondition failed")
	}

	return s.updateExistingComment(ctx, ghclient, updatedJob, repo, body)
}

func (s *Service) updateExistingComment(ctx context.Context, ghclient github.ClientInterface, job *jobs.Job, repo *gg.Repository, body string) error {
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

// truncateUTF8 truncates a string to at most maxLen bytes without splitting
// multi-byte UTF-8 runes.
func truncateUTF8(s string, maxLen int) string {
	if len(s) <= maxLen {
		return s
	}
	runes := []rune(s)
	result := string(runes)
	for len(result) > maxLen {
		runes = runes[:len(runes)-1]
		result = string(runes)
	}
	return result
}
