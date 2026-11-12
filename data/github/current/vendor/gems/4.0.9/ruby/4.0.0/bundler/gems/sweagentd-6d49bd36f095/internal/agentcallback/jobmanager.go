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
	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/jobs"
	js "github.com/github/sweagentd/internal/jobservice"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/tips"
	gg "github.com/google/go-github/v75/github"
)

type jobManager struct {
	obsv        observability.Exporters
	jobService  jobservice
	jobsStore   jobstore
	clients     github.ClientFactoryInterface
	ghTwirp     githubtwirp.ClientInterface
	ffClient    featureflags.Client
	appProvider *agenticapp.Provider
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

func newManager(
	obsv observability.Exporters,
	jobService jobservice,
	jobsStore jobstore,
	clients github.ClientFactoryInterface,
	ghTwirp githubtwirp.ClientInterface,
	ffClient featureflags.Client,
	appProvider *agenticapp.Provider,
) *jobManager {
	return &jobManager{
		obsv,
		jobService,
		jobsStore,
		clients,
		ghTwirp,
		ffClient,
		appProvider,
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
					err = goerrors.Errorf("failed to process agent update, check logs for detail: %w", err)
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
	case AgentUpdateKindCheckQuota:
		result, err = m.handleCheckQuota(ctx, r, job)
	default:
		return nil, &badRequestError{"unknown update kind: " + string(update.Kind)}
	}
	if err != nil {
		return nil, err
	}

	err = m.jobService.UpdateFromExecutionResult(ctx, job, result.Status, result.RunningAt)
	if err != nil {
		return nil, goerrors.Errorf("failed to update job: %w", err)
	}

	return result.Response, nil
}

// JobResult represents the result of a job execution
type JobResult struct {
	Status      jobs.JobStatus `json:"status"`
	CompletedAt time.Time      `json:"completedAt"`
	RunningAt   time.Time      `json:"-"`
	Result      any            `json:"result"`
	// Response will be sent back to the caller, if applicable, if not nil
	Response any `json:"response"`
}

// updatePullRequest creates or updates the title and body of a pull request.
// If the title or body has changed, the pull request is updated.
// Updates are skipped for PRs not authored by Copilot to avoid overwriting human-authored content.
func (m *jobManager) updatePullRequest(ctx context.Context, gh github.ClientInterface, job *jobs.Job, repo *gg.Repository, title, body *string) error {
	pr, err := gh.GetPullRequest(ctx, job.RepoID, job.PullRequestNumber)
	if err != nil {
		return goerrors.Errorf("failed to get pull request: %w", err)
	}

	if _, isAgentic := m.appProvider.IsAgenticActor(pr.GetUser()); !isAgentic {
		m.obsv.LoggerWithTelemetry(ctx).Debug(fmt.Sprintf("skipping PR update: PR was not authored by agent (repo_id=%d, pr_number=%d)", job.RepoID, job.PullRequestNumber))
		return nil
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
		newBody, bodyChanged := m.processBodyUpdate(ctx, job, repo, pr.GetBody(), strings.TrimSpace(*body))
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
func (m *jobManager) processBodyUpdate(ctx context.Context, job *jobs.Job, repo *gg.Repository, currentPRBody, newCoreBody string) (string, bool) {
	currentCoreBody, currentSuffix, currentTip := m.extractCoreBodyAndSuffixFromPR(currentPRBody)

	newBody := newCoreBody

	// Add suffix
	suffixToAdd := m.determineSuffixToAdd(job, currentSuffix)
	if suffixToAdd != "" {
		newBody += suffixToAdd
	}

	// Add tip
	tipToAdd := m.determineTipToAdd(ctx, job, repo, currentTip)
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
		if strings.Contains(bodySuffix, js.PullRequestBodySuffixSeparator) {
			return bodySuffix
		}
		return js.PullRequestBodySuffixSeparator + bodySuffix
	}
	return currentSuffix
}

// determineTipToAdd determines what tip should be added to the body
func (m *jobManager) determineTipToAdd(ctx context.Context, job *jobs.Job, repo *gg.Repository, currentTip string) string {
	if currentTip != "" {
		return currentTip
	}

	if !m.appProvider.IsCopilotApp(job.AgentID) {
		return ""
	}

	tip := tips.GetRandomTipForJob(ctx, m.ffClient, job, repo)
	if tip == "" {
		return ""
	}

	return tips.PullRequestBodyTipSeparator + tip
}

// extractCoreBodyAndSuffixFromPR extracts the core body, suffix, and tip from a pull request body
func (m *jobManager) extractCoreBodyAndSuffixFromPR(prBody string) (core, suffix, tip string) {
	originalPromptIndex := strings.Index(prBody, js.PullRequestBodyOriginalPromptSeparator)
	suffixIndex := strings.Index(prBody, js.PullRequestBodySuffixSeparator)
	tipIndex := strings.Index(prBody, tips.PullRequestBodyTipSeparator)

	// Find where suffix content starts (whichever separator comes first)
	suffixContentStart := -1
	if originalPromptIndex != -1 && (suffixIndex == -1 || originalPromptIndex < suffixIndex) {
		suffixContentStart = originalPromptIndex // Original prompt comes first (new format)
	} else if suffixIndex != -1 {
		suffixContentStart = suffixIndex // User suffix comes first (old format)
	}

	// Extract sections based on what we found
	switch {
	case suffixContentStart != -1 && tipIndex != -1 && suffixContentStart < tipIndex:
		// Core -> Suffix -> Tip
		core = prBody[:suffixContentStart]
		suffix = prBody[suffixContentStart:tipIndex]
		tip = prBody[tipIndex:]
	case suffixContentStart != -1 && tipIndex != -1 && tipIndex < suffixContentStart:
		// Core -> Tip -> Suffix (unusual but handle it)
		core = prBody[:tipIndex]
		tip = prBody[tipIndex:suffixContentStart]
		suffix = prBody[suffixContentStart:]
	case suffixContentStart != -1:
		// Core -> Suffix (no tip)
		core = prBody[:suffixContentStart]
		suffix = prBody[suffixContentStart:]
	case tipIndex != -1:
		// Core -> Tip (no suffix)
		core = prBody[:tipIndex]
		tip = prBody[tipIndex:]
	default:
		// Just core (no separators)
		core = prBody
	}

	return core, suffix, tip
}
