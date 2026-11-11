// Package events handles hydro events and processes them.
package events

import (
	"context"
	"fmt"
	"strings"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobservice"
	"github.com/github/sweagentd/internal/jobutils"
	"github.com/github/sweagentd/internal/limiter"
	"github.com/github/sweagentd/internal/problemstatement"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/sweagentd"
)

func (h *Handler) OnPullRequestCommentCreated(ctx context.Context, event PullRequestCommentCreatedEvent) error {
	assignment, err := h.assignmentForPR(ctx, event.Repo.OwnerID, event.Repo.ID, nil, &event.PullRequest.Number)
	if err != nil {
		return fmt.Errorf("failed to get assignment for pull request: %w", err)
	}

	app, err := h.appProvider.FindByID(event.AgentID)
	if err != nil {
		return fmt.Errorf("failed to find app by ID from comment: %w", err)
	}

	// Check for mention of model selection
	mentionResult, commentMentionsAgenticActor := h.appProvider.IsAgenticMentionWithModel(event.Comment.Body)
	var requestedModel string
	if mentionResult != nil && h.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentPRCommentModelPicker, &event) {
		requestedModel = mentionResult.Model
		if requestedModel != "" {
			h.obsv.Increment(ctx, "events.on_pull_request_comment_created.model_picker_requested", stats.Tags{
				"model": requestedModel,
			})
			h.obsv.LoggerWithTelemetry(ctx).Info("Model picker requested via PR comment mention",
				kvp.String("requested_model", requestedModel))
		}
	}

	if assignment == nil && !commentMentionsAgenticActor {
		h.obsv.LoggerWithTelemetry(ctx).Info("No assignment found for pull request and not opening stacked PR, skipping comment processing")
		return nil
	}

	ignore, err := h.ShouldIgnorePRCommentOrReview(ctx, event.PullRequest, event.Actor)
	if err != nil {
		return fmt.Errorf("failed to check if comment should be ignored: %w", err)
	}
	if ignore {
		return nil
	}

	h.obsv.Statter.Counter("events.on_pull_request_comment_created.handled", nil, 1)

	gh, err := h.ghFactory.NewClientForRepo(ctx, app, &event)
	if err != nil {
		return fmt.Errorf("failed to create GitHub client: %w", err)
	}

	hasPermissions, err := h.PRCommentOrReviewAuthorHasPushPermissions(ctx, gh, event.Repo, event.Actor)
	if err != nil {
		return fmt.Errorf("failed to check if author has push permissions: %w", err)
	}
	if !hasPermissions {
		return nil
	}

	actx, err := gh.GetPullRequestContext(ctx, event.Repo.NodeID, event.PullRequest.Number, h.appProvider.IsAgenticActor)
	if err != nil {
		return fmt.Errorf("failed to get pull request context: %w", err)
	}

	if actx.PullRequest.IsCrossRepository {
		h.obsv.LoggerWithTelemetry(ctx).Info("Ignoring comment because it is on a cross-repository pull request")
		return nil
	}

	h.setCtxPullRequestID(ctx, actx.PullRequest.GetID(), actx.PullRequest.Number)

	// The user commented on a non-Agentic PR, @-mentioning Agentic.
	_, isAgenticAuthor := h.appProvider.IsAgenticActor(actx.PullRequest.Author)
	if commentMentionsAgenticActor && !isAgenticAuthor {
		h.obsv.Increment(ctx, "events.handle_comment_on_non_copilot_authored_pr", nil)
		err = h.handleCommentOnNonCopilotAuthoredPullRequest(ctx, gh, assignment, actx, event, app, requestedModel)
		if err != nil && jobservice.IsBuilderFinalizedJobError(err) {
			return nil
		}
		return err
	}

	err = h.onPullRequestCommentCreated(ctx, gh, assignment, actx, event, commentMentionsAgenticActor, app, requestedModel)
	if err != nil {
		if jobservice.IsBuilderFinalizedJobError(err) {
			return nil
		}
		if limiter.IsAnyLimiterError(err) {
			return err
		}

		// TODO: (colbylwilliams) determine if we still need this
		return jobutils.NewUnhandledErrorWithPRComment(ctx, err, assignment, event.Actor.Login)
	}

	return nil
}

func (h *Handler) onPullRequestCommentCreated(
	ctx context.Context,
	gh github.ClientInterface,
	assignment *jobs.Assignment,
	actx *github.PullRequestContext,
	event PullRequestCommentCreatedEvent,
	agenticMention bool,
	app sweagentd.AgenticApp,
	requestedModel string,
) error {
	ctx, span := h.obsv.Tracer.Start(ctx, "events.Handler.onPullRequestCommentCreated")
	defer span.End()

	pr := actx.PullRequest
	repo := actx.Repository
	owner := repo.Owner

	logger := h.obsv.LoggerWithTelemetry(ctx)

	logger.Info("processing pull request comment")

	comment := pr.CommentByID(event.Comment.ID)
	if comment == nil {
		return fmt.Errorf("failed to get pull request comment")
	}

	// Double check that the comment author matches the event actor
	if comment.Author.GetID() != event.Actor.ID {
		return fmt.Errorf("comment author does not match event actor")
	}
	// Ignore events for closed PRs
	if pr.IsClosed() {
		logger.Info("Ignoring comment because pull request is closed")
		return nil
	}

	_, isAgenticActor := h.appProvider.IsAgenticActor(pr.Author)
	workOnCurrentBranch := h.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentWorkOnCurrentBranch, &event)
	if !isAgenticActor && !workOnCurrentBranch {
		logger.Info("Ignoring comment because pull request is not authored by Copilot")
		return nil
	}

	// Ignore comments authored by Copilot or other bots
	_, isAgenticActor = h.appProvider.IsAgenticActor(comment.Author)
	if isAgenticActor || comment.Author.IsBot() {
		logger.Info("Ignoring comment because it was authored by Copilot or a bot")
		return nil
	}

	// Only process events where the actor has write access to the repo
	if !actx.PermissionsFor(comment.Author).Push {
		logger.Info("Ignoring comment because actor does not have write access to the repo")
		return nil
	}

	// Only wake if the comment mentions an Agent
	if !agenticMention {
		logger.Info("Ignoring review because it does not mention an Agent")
		return nil
	}

	logger.Info("Waking up Agent because new feedback is actionable")

	// ✅ All validation/permission checks passed, now we start doing things

	// Add a 👀 reaction to acknowledge the (actionable) comment
	if err := comment.AddReaction(ctx, gh, github.GQLReactionContentEyes); err != nil {
		// Bummer, but we don't want to fail the job
		h.obsv.LogAndReportError(ctx, err, "failed to add reaction")
	}

	// Fetch repository information from GitHub API
	ggRepo, err := gh.GetRepositoryByID(ctx, repo.ID)
	if err != nil {
		return goerrors.Errorf("failed to get repository: %w", err)
	}

	var allJobs []*jobs.Job
	var pendingJob *jobs.Job

	if assignment != nil {
		allJobs, pendingJob, err = jobutils.JobsForAssignment(ctx, h.obsv, h.jobService, gh, h.ffClient, assignment, ggRepo)
		if err != nil {
			return fmt.Errorf("failed to get jobs for assignment: %w", err)
		}
	}

	actor, err := h.getJobActor(ctx, event.Actor)
	if err != nil {
		return fmt.Errorf("failed to get job actor: %w", err)
	}

	// Find the most recent job's model to use for the new job
	mostRecentJob := getMostRecentJob(allJobs)

	var builder *jobservice.JobBuilderWithAssignmentAndActor

	if pendingJob == nil {
		baseBuilder := h.jobService.NewJobBuilder(jobs.AgentActionFixPRComment, ggRepo, pr.HeadRef.Name)

		if assignment == nil {
			// Create new assignment for non-Copilot PRs working on current branch
			useAsyncSessions := h.ffClient.IsEnabledForUserOrRepo(ctx, featureflags.CopilotSWEAgentUseAsyncSessions, actor.ID, repo.ID)
			builder = baseBuilder.
				WithNewAssignment(owner.GetID(), repo.ID, owner.NodeID, repo.NodeID, owner.Login, repo.Name, useAsyncSessions, pullRequestResource(pr.GetID())).
				WithJobActor(*actor)
		} else {
			builder = baseBuilder.
				ForAssignment(assignment).
				WithJobActor(*actor)
		}
	} else {
		builder = h.jobService.
			JobBuilderForJob(assignment, pendingJob, ggRepo).
			WithJobActor(*actor)
	}

	builder = builder.
		WithModel(requestedModel).
		WithJobInitHook(func(j *jobs.Job) {
			// Priority for model selection:
			// 1. Explicit model from mention (e.g., "@copilot+claude-opus.4.5") via JobBuilder.WithModel/DetermineModel
			// 2. Inherited model from most recent job
			// 3. Auto model selection
			if shouldInheritModel(assignment, mostRecentJob, requestedModel) {
				// Inherit the most recent model used in prior jobs for this PR. This takes precedence over any
				// auto model selection.
				j.Model = mostRecentJob.Model
			}
			j.BranchName = pr.HeadRef.Name
			// Make sure this comment is added to the pending job so the LLM considers it
			j.CommentIDs = append(j.CommentIDs, comment.GetID())
			// Add all other (qualifying) comments and reviews that haven't been included on a job yet.
			jobutils.AddUnprocessedCommentsAndReviewsToJob(gh, actx, allJobs, j, h.appProvider.IsAgenticActor)
		}).
		WithEvent(jobservice.Event{
			Type:        jobs.EventTypePullRequestComment,
			URL:         event.EventUrl,
			Identifiers: []string{fmt.Sprintf("%d", comment.GetID())},
		}).
		WithProblemStatementBuilder(func(c context.Context, j *jobs.Job) (jobs.ProblemStatement, error) {
			return problemstatement.NewPullRequestBuilder(h.obsv, actx, j, githubtwirp.NewAuthorResolver(h.obsv, h.ghTwirp, h.ffClient), h.appProvider).Build(c)
		}).
		WithAgentID(app.AppID())

	if has, runningJobID := jobs.HasQueuedOrRunningJobs(allJobs); has {
		h.obsv.LoggerWithTelemetry(ctx).Info("Job pending but not launching agent because there is another job in progress",
			kvp.String("running_job_id", runningJobID))

		_, _, err = builder.Build(ctx, gh)
		if err != nil {
			return fmt.Errorf("failed to build job: %w", err)
		}
		return nil
	}

	_, pendingJob, err = builder.WithNewSession().WithAINameGen().Build(ctx, gh)
	if err != nil {
		return fmt.Errorf("failed to build job: %w", err)
	}

	h.obsv.LoggerWithTelemetry(ctx).Info("Queuing new job for pull request")

	_, err = h.jobService.QueueJobForExecution(ctx, pendingJob)
	if err != nil {
		return fmt.Errorf("failed to queue job: %w", err)
	}

	return nil
}

// setCtxPullRequestID updates the pull request in the request context with an ID.
// The pull request is added to the context during the initial hydro event processing,
// but the event that triggers the OnPullRequestCommentCreated handler doesn't include
// the pull request ID (because the PR is represented as an issue). This function
// is used to backfill the ID value once we have it.
func (h *Handler) setCtxPullRequestID(ctx context.Context, id int64, number int) {
	pr, ok := requestctx.PullRequest(ctx)
	if ok && pr.Number == number && pr.ID == nil {
		pr.ID = &id
		if err := requestctx.AddPullRequest(ctx, *pr); err != nil {
			h.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to add pull request to context")
		}
	}
}

func (h *Handler) handleCommentOnNonCopilotAuthoredPullRequest(ctx context.Context, gh github.ClientInterface, assignment *jobs.Assignment, actx *github.PullRequestContext, event PullRequestCommentCreatedEvent, app sweagentd.AgenticApp, requestedModel string) error {
	ctx, span := h.obsv.Tracer.Start(ctx, "events.Handler.handleCommentOnNonCopilotAuthoredPullRequest")
	defer span.End()
	if h.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentWorkOnCurrentBranch, &event) {
		return h.createCommentJobOnCurrentBranch(ctx, gh, assignment, actx, event, app, requestedModel)
	}
	return h.createCommentJobWithStackedPR(ctx, gh, actx, event, app, requestedModel)
}

func (h *Handler) createCommentJobOnCurrentBranch(ctx context.Context, gh github.ClientInterface, assignment *jobs.Assignment, actx *github.PullRequestContext, event PullRequestCommentCreatedEvent, app sweagentd.AgenticApp, requestedModel string) error {
	ctx, span := h.obsv.Tracer.Start(ctx, "events.Handler.createCommentJobOnCurrentBranch")
	defer span.End()

	h.obsv.Increment(ctx, "events.handle_comment_on_non_copilot_authored_pr.work_on_current_branch", nil)
	h.obsv.LoggerWithTelemetry(ctx).Info("Handling comment on non-Copilot-authored PR by working on current branch")

	return h.onPullRequestCommentCreated(ctx, gh, assignment, actx, event, true, app, requestedModel)
}

func (h *Handler) createCommentJobWithStackedPR(ctx context.Context, gh github.ClientInterface, actx *github.PullRequestContext, event PullRequestCommentCreatedEvent, app sweagentd.AgenticApp, requestedModel string) error {
	ctx, span := h.obsv.Tracer.Start(ctx, "events.Handler.createCommentJobWithStackedPR")
	defer span.End()

	h.obsv.Increment(ctx, "events.handle_comment_on_non_copilot_authored_pr.stacked_pr", nil)
	h.obsv.LoggerWithTelemetry(ctx).Info("Handling comment on non-Copilot-authored PR by working with a stacked PR")

	pr := actx.PullRequest
	repo := actx.Repository
	owner := repo.Owner

	logger := h.obsv.LoggerWithTelemetry(ctx)
	logger.Info("processing comment on non-Copilot-authored PR to create stacked PR")

	jobActor, err := h.getJobActor(ctx, event.Actor)
	if err != nil {
		return fmt.Errorf("failed to get job actor: %w", err)
	}

	// Get the comment that triggered this event
	comment := pr.CommentByID(event.Comment.ID)
	if comment == nil {
		return fmt.Errorf("failed to get pull request comment")
	}

	// Add a 👀 reaction to indicate we've started work
	if err := comment.AddReaction(ctx, gh, github.GQLReactionContentEyes); err != nil {
		h.obsv.LogAndReportError(ctx, err, "failed to add reaction")
	}

	// Fetch repository from GitHub API
	ggRepo, err := gh.GetRepositoryByID(ctx, repo.ID)
	if err != nil {
		return goerrors.Errorf("failed to get repository: %w", err)
	}

	useAsyncSessions := h.ffClient.IsEnabledForUserOrRepo(ctx, featureflags.CopilotSWEAgentUseAsyncSessions, jobActor.ID, repo.ID)

	_, job, err := h.jobService.
		NewJobBuilder(jobs.AgentActionFixPRComment, ggRepo, pr.HeadRef.Name).
		WithNewAssignment(owner.GetID(), repo.ID, owner.NodeID, repo.NodeID, owner.Login, repo.Name, useAsyncSessions, pullRequestResource(pr.GetID())).
		WithJobActor(*jobActor).
		WithModel(requestedModel). // no-op if empty, routes through DetermineModel validation
		WithProblemStatementBuilder(func(c context.Context, j *jobs.Job) (jobs.ProblemStatement, error) {
			// Create problem statement for the stack PR
			// Importantly, the `actx` is still for the original PR, which is what we want
			// since we want the problem statement to reflect the full context of the original PR
			// and the comment that triggered the stack PR creation.
			return problemstatement.NewPullRequestBuilder(h.obsv, actx, j, githubtwirp.NewAuthorResolver(h.obsv, h.ghTwirp, h.ffClient), h.appProvider).Build(c)
		}).
		WithJobInitHook(func(j *jobs.Job) {
			// Add the comment ID to the job so it gets processed
			j.CommentIDs = append(j.CommentIDs, comment.GetID())
		}).
		WithEvent(jobservice.Event{
			Type:        jobs.EventTypePullRequestCommentNonCopilotPullRequest,
			URL:         event.EventUrl,
			Identifiers: eventIdentifiers(comment.GetID()),
			Content:     comment.GetBody(),
		}).
		WithFeaturesBuilder(func(c context.Context, j *jobs.Job) jobs.EnvironmentFeatures {
			title, err := h.generateStackPRTitle(c, j, pr.Title, comment.Body)
			if err != nil {
				// Fallback to default title if generation fails
				h.obsv.LogAndReportError(c, err, "failed to generate stack PR title")
				title = fmt.Sprintf("[WIP] Make requested changes to #%d", pr.Number)
			}

			body := fmt.Sprintf("Triggering comment (%s):\n> %s\n", comment.GetURL(), strings.ReplaceAll(comment.GetBody(), "\n", "\n> "))
			return jobs.EnvironmentFeatures{
				PullRequest: &jobs.PullRequestFeature{
					TitlePlaceholder: title,
					BodyPlaceholder:  getStackedPRBodyBase(pr, body),
				},
				Branch: &jobs.BranchFeature{
					Name: fmt.Sprintf("%s%d", stackedPRPrefix, pr.Number),
				},
			}
		}).
		WithAgentID(app.AppID()).
		WithNewSession().
		WithAINameGen().
		Build(ctx, gh)
	if err != nil {
		return fmt.Errorf("failed to build job: %w", err)
	}

	h.obsv.LoggerWithTelemetry(ctx).Info("Queuing new job for stack PR")

	_, err = h.jobService.QueueJobForExecution(ctx, job)
	if err != nil {
		return fmt.Errorf("failed to queue job: %w", err)
	}

	// Comment on the original PR to let the user know where the work is happening
	commentBody := fmt.Sprintf("@%s I've opened a new pull request, #%d, to work on those changes. Once the pull request is ready, I'll request review from you.", jobActor.DisplayLogin, job.PullRequestNumber)
	if _, err := gh.CreateComment(ctx, int64(repo.ID), pr.Number, commentBody); err != nil {
		// Log the error but don't fail the entire operation
		h.obsv.LogAndReportError(ctx, err, "failed to comment on original PR")
	}

	return nil
}

func (h *Handler) getJobActor(ctx context.Context, actor *Actor) (*jobs.JobActor, error) {
	jobActor := &jobs.JobActor{
		ID:           actor.ID,
		Login:        actor.Login,
		DisplayLogin: actor.DisplayLogin,
		TrackingID:   actor.TrackingID,
	}

	if jobActor.DisplayLogin == "" {
		err := jobActor.FillDisplayLogin(ctx, h.obsv, h.ffClient, h.ghTwirp, uint64(actor.ID))
		if err != nil {
			return nil, fmt.Errorf("failed to fill display login for job actor: %w", err)
		}
	}

	if jobActor.TrackingID == "" {
		userDetails, err := h.ghTwirp.GetCopilotUserDetails(ctx, actor.ID)
		if err != nil {
			h.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to get copilot user for tracking ID")
		} else {
			jobActor.TrackingID = userDetails.AnalyticsTrackingId
		}
	}

	return jobActor, nil
}
