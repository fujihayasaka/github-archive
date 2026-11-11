package agentcallback

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/github/go-mark"
	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/jobs"
	db "github.com/github/sweagentd/internal/jobs/store"
	"github.com/github/sweagentd/internal/jobutils"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/tips"
)

type jobManager struct {
	obsv       observability.Exporters
	jobService jobservice
	jobsStore  jobstore
	clients    github.ClientFactoryInterface
	ghTwirp    githubtwirp.ClientInterface
	ffClient   featureflags.Client
}

// ProgressResponse represents the response for handling a job update of kind=progress.
// It implements JobResponse.
type ProgressResponse struct {
	// User Messages to send back to incorporate into the Agent loop
	UserMessages []UserMessageResponse `json:"user_messages"`
}

// UserMessageResponse represents a message sent by a user that we want to provide the agent with.
type UserMessageResponse struct {
	// The ID of the user message command
	ID string `json:"id"`
	// The GitHub user ID for the user associated with this command
	ActorID int64 `json:"actor_id"`
	// The raw command content as provided by the session service
	Content string `json:"content"`
	// The Unix timestamp when the command when this command was submitted (either by our service or an external service)
	Timestamp int64 `json:"timestamp"`
}

func newManager(obsv observability.Exporters, jobService jobservice, jobsStore jobstore, clients github.ClientFactoryInterface, ghTwirp githubtwirp.ClientInterface, ffClient featureflags.Client) *jobManager {
	return &jobManager{
		obsv,
		jobService,
		jobsStore,
		clients,
		ghTwirp,
		ffClient,
	}
}

func (m *jobManager) HandleJobUpdate(ctx context.Context, r *http.Request, job *jobs.Job, update JobUpdate, actorID int64) (resp any, err error) {
	// Ensure that the job is for the correct actor
	if job.ActorID != actorID {
		return nil, mark.ErrNotFound
	}

	if job.Status.IsTerminal() {
		return nil, &badRequestError{"job is in a terminal state: " + string(job.Status)}
	}

	var result *JobResult
	// If we error, we want to clean up the container and ensure we set the job status to a terminal state
	defer func() {
		var badRequestErr *badRequestError
		if err != nil && !errors.As(err, &badRequestErr) {
			m.obsv.LoggerWithRequestTelemetry(ctx, r).Error(fmt.Sprintf("Failed to handle result: %s", err))

			if job != nil {
				if result == nil {
					update.Kind = AgentUpdateKindError
					m.UpdateRequestContextJobUpdate(ctx, &update, job.Action)
					m.obsv.LoggerWithRequestTelemetry(ctx, r).Error("Job failed without a result")
					err = fmt.Errorf("failed to process agent update, check logs for detail: %w", err)
					return
				}
			}
		}
	}()

	tags := m.obsv.TelemetryTags(ctx).Merge(stats.Tags{"kind": string(update.Kind)})
	m.obsv.Statter.Counter("agent.runtime_update", tags, 1)

	switch update.Kind {
	case AgentUpdateKindResult:
		result, err = m.handleResult(ctx, r, job, update)
	case AgentUpdateKindProgress:
		result, err = m.handleProgress(ctx, r, job, update)
	case AgentUpdateKindPartialResult:
		result, err = m.handlePartialResult(ctx, r, job, update)
	case AgentUpdateKindCommentReply:
		result, err = m.handleCommentReply(ctx, r, job, update)
	case AgentUpdateKindError:
		result, err = m.handleError(ctx, r, job, update)
	default:
		return nil, &badRequestError{"unknown update kind: " + string(update.Kind)}
	}
	if err != nil {
		return nil, err
	}

	// Update the job status if it has changed, but only if the new status
	// is not terminal. We set the status to terminal states upon workflow
	// run completion where we also finalize the session.
	if job.Status != result.Status && !result.Status.IsTerminal() {
		prevJobStatus := job.Status

		// TODO (colbylwilliams): will it be set to "running" here?
		err = m.jobsStore.PatchJob(ctx, job, db.JobPatch{Status: &result.Status})
		if err != nil {
			return nil, fmt.Errorf("failed to patch job: %w", err)
		}

		jobs.StatJobTransition(ctx, m.obsv, m.obsv.TelemetryTags(ctx), prevJobStatus, result.Status)
	}

	return result.Response, nil
}

// JobResult represents the result of a job execution
type JobResult struct {
	Status      jobs.JobStatus `json:"status"`
	CompletedAt time.Time      `json:"completedAt"`
	Result      any            `json:"result"`
	// Response will be sent back to the caller, if applicable, if not nil
	Response any `json:"response"`
}

// updatePullRequest creates or updates the title and body of a pull request.
// If the title or body has changed, the pull request is updated
func (m *jobManager) updatePullRequest(ctx context.Context, gh github.ClientInterface, job *jobs.Job, title, body *string) error {
	pr, err := gh.GetPullRequest(ctx, job.RepoID, job.PullRequestNumber)
	if err != nil {
		return fmt.Errorf("failed to get pull request: %w", err)
	}

	needsUpdate := false

	var newTitle string
	if title != nil {
		newTitle = strings.TrimSpace(*title)
		if len(newTitle) > github.MaxPullRequestTitleLength {
			newTitle = newTitle[:github.MaxPullRequestTitleLength-3] + "..."
		}
	}

	if newTitle != "" && newTitle != pr.GetTitle() {
		pr.Title = &newTitle
		needsUpdate = true
	}

	if body != nil {
		newBody, bodyChanged := m.processBodyUpdate(ctx, job, pr.GetBody(), strings.TrimSpace(*body))
		if bodyChanged {
			pr.Body = &newBody
			needsUpdate = true
		}
	}

	if needsUpdate {
		_, err = gh.UpdatePullRequest(ctx, job.RepoID, pr)
		return err
	}

	return nil
}

// processBodyUpdate processes the body update logic and returns the new body and whether it changed
func (m *jobManager) processBodyUpdate(ctx context.Context, job *jobs.Job, currentPRBody, newCoreBody string) (string, bool) {
	currentCoreBody, currentSuffix, currentTip := m.extractCoreBodyAndSuffixFromPR(currentPRBody)

	newBody := newCoreBody

	// Add suffix
	suffixToAdd := m.determineSuffixToAdd(job, currentSuffix)
	if suffixToAdd != "" {
		newBody += suffixToAdd
	}

	// Add tip
	tipToAdd := m.determineTipToAdd(ctx, job, currentTip)
	if tipToAdd != "" {
		newBody += tipToAdd
	}

	return newBody, currentCoreBody != newCoreBody
}

// determineSuffixToAdd determines what suffix should be added to the body
func (m *jobManager) determineSuffixToAdd(job *jobs.Job, currentSuffix string) string {
	bodySuffix := job.PullRequestBodySuffix()
	if bodySuffix != "" {
		// If the current suffix already contains the separator, don't add it again
		if strings.Contains(bodySuffix, jobutils.PullRequestBodySuffixSeparator) {
			return bodySuffix
		}
		return jobutils.PullRequestBodySuffixSeparator + bodySuffix
	}
	return currentSuffix
}

// determineTipToAdd determines what tip should be added to the body
func (m *jobManager) determineTipToAdd(ctx context.Context, job *jobs.Job, currentTip string) string {
	if currentTip != "" {
		return currentTip
	}

	tip := tips.GetRandomTipForJob(ctx, m.ffClient, job)
	if tip == "" {
		return ""
	}

	return tips.PullRequestBodyTipSeparator + tip
}

// extractCoreBodyAndSuffixFromPR extracts the core body, suffix, and tip from a pull request body
func (m *jobManager) extractCoreBodyAndSuffixFromPR(prBody string) (core, suffix, tip string) {
	suffixIndex := strings.Index(prBody, jobutils.PullRequestBodySuffixSeparator)
	tipIndex := strings.Index(prBody, tips.PullRequestBodyTipSeparator)

	if suffixIndex != -1 && tipIndex != -1 {
		if suffixIndex < tipIndex {
			// expected order: core -> suffix -> tip
			core = prBody[:suffixIndex]
			suffix = prBody[suffixIndex:tipIndex]
			tip = prBody[tipIndex:]
		} else {
			// unexpected order: core -> tip -> suffix (shouldn't happen)
			core = prBody[:tipIndex]
			suffix = prBody[suffixIndex:]
			tip = prBody[tipIndex:suffixIndex]
		}
		return core, suffix, tip
	}

	// only suffix exists
	if suffixIndex != -1 {
		return prBody[:suffixIndex], prBody[suffixIndex:], ""
	}

	// only tip exists
	if tipIndex != -1 {
		return prBody[:tipIndex], "", prBody[tipIndex:]
	}

	// no separators found
	return prBody, "", ""
}
