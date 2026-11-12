// Package events handles hydro events and processes them.
package events

import (
	"cmp"
	"context"
	"errors"
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
	app, err := h.appProvider.FindByID(ctx, event.AgentID)
	if err != nil {
		return goerrors.Errorf("failed to find app by ID from comment: %w", err)
	}

	// Parse @-mention and optional model selection (e.g., "@copilot+claude-opus.4.5")
	mentionResult, commentMentionsAgent := h.appProvider.IsAgenticMentionWithModel(event.Comment.Body)
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

	ignore, err := h.ShouldIgnorePRCommentOrReview(ctx, event.PullRequest, event.Actor)
	if err != nil {
		return goerrors.Errorf("failed to check if comment should be ignored: %w", err)
	}
	if ignore {
		return nil
	}

	gh, err := h.ghFactory.NewClientForRepo(ctx, app, &event)
	if err != nil {
		return goerrors.Errorf("failed to create GitHub client: %w", err)
	}

	hasPermissions, err := h.PRCommentOrReviewAuthorHasPushPermissions(ctx, gh, event.Repo, event.Actor)
	if err != nil {
		return goerrors.Errorf("failed to check if author has push permissions: %w", err)
	}
	if !hasPermissions {
		return nil
	}

	var appWorkflowsAccess *bool
	if event.GitHubAppID != nil && h.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentCheckGitHubAppPermissions, &event) {
		contents, workflows, err := h.appPermissionsForRepository(ctx, *event.GitHubAppID, event.Repo.ID)
		if err != nil {
			return goerrors.Errorf("failed to check originating GitHub App permissions: %w", err)
		}
		if !contents {
			h.obsv.LoggerWithTelemetry(ctx).Info("Ignoring comment because originating GitHub App lacks contents:write",
				kvp.Int64("github_app_id", *event.GitHubAppID))
			return nil
		}
		appWorkflowsAccess = h.recordAppWorkflowsAccess(ctx, &event, workflows)
	}

	actx, err := gh.GetPullRequestContext(ctx, event.Repo.NodeID, event.PullRequest.Number, h.appProvider.IsAgenticActor)
	if err != nil {
		return goerrors.Errorf("failed to get pull request context: %w", err)
	}

	if actx.PullRequest.IsCrossRepository {
		h.obsv.LoggerWithTelemetry(ctx).Info("Ignoring comment because it is on a cross-repository pull request")
		return nil
	}

	h.setCtxPullRequestID(ctx, actx.PullRequest.GetID(), actx.PullRequest.Number)

	// Assignment lookup
	prID := actx.PullRequest.GetID()
	assignment, err := h.assignmentForPR(ctx, &event, &prID, &event.PullRequest.Number)
	if err != nil {
		return goerrors.Errorf("failed to get assignment for pull request: %w", err)
	}

	if assignment == nil && !commentMentionsAgent {
		h.obsv.LoggerWithTelemetry(ctx).Info("No assignment found for pull request and comment does not mention agent, skipping")
		return nil
	}

	h.obsv.Increment(ctx, "events.on_pull_request_comment_created.handled", nil)

	// Process the comment: validate, determine action (stacked PR vs current branch), and execute
	err = h.onPullRequestCommentCreated(ctx, gh, assignment, actx, event, commentMentionsAgent, app, requestedModel, appWorkflowsAccess)
	return h.handlePRCommentError(ctx, err, assignment, event.Actor.Login, requestedModel, event)
}

// handlePRCommentError translates specific error types from processPRComment into
// appropriate responses (e.g., user-facing error comments on the PR).
func (h *Handler) handlePRCommentError(ctx context.Context, err error, assignment *jobs.Assignment, actorLogin, requestedModel string, event PullRequestCommentCreatedEvent) error {
	if err == nil {
		return nil
	}

	// Ensure we have an assignment so error comments can be posted back to the PR
	if assignment == nil && event.Repo != nil {
		assignment = &jobs.Assignment{
			RepoID:            event.Repo.ID,
			OwnerID:           event.Repo.OwnerID,
			PullRequestNumber: event.PullRequest.Number,
		}
	}

	// If the error is already a user-visible comment pass it through as is
	var userVisibleErr *jobutils.UserVisibleCommentForUnhandledError
	if errors.As(err, &userVisibleErr) {
		return err
	}
	if jobservice.IsBuilderFinalizedJobError(err) {
		var rulesErr *jobservice.RulesViolationError
		if errors.As(err, &rulesErr) {
			return jobutils.NewRulesViolationErrorWithPRComment(ctx, err, assignment, actorLogin, rulesErr.CheckRulesResult)
		}
		return nil
	}
	if limiter.IsAnyLimiterError(err) {
		return err
	}
	if errors.Is(err, jobservice.ErrModelNotFound) || errors.Is(err, jobservice.ErrNoModelAvailable) || errors.Is(err, jobservice.ErrModelVendorMismatch) {
		h.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("model selection failed for PR comment",
			kvp.String("requested_model", requestedModel))
		return jobutils.NewModelNotAvailableErrorWithPRComment(ctx, err, assignment, actorLogin, requestedModel)
	}
	// TODO: (colbylwilliams) determine if we still need this
	return jobutils.NewUnhandledErrorWithPRComment(ctx, err, assignment, actorLogin)
}

// onPullRequestCommentCreated validates the comment, determines whether to work on the current
// branch or create a stacked PR, and dispatches to the appropriate job builder.
//
// This is the unified entry point for both agent-authored and human-authored PRs.
// The decision of stacked PR vs current branch is made once in shouldCreateStackedPR.
func (h *Handler) onPullRequestCommentCreated(
	ctx context.Context,
	gh github.ClientInterface,
	assignment *jobs.Assignment,
	actx *github.PullRequestContext,
	event PullRequestCommentCreatedEvent,
	commentMentionsAgent bool,
	app sweagentd.AgenticApp,
	requestedModel string,
	appWorkflowsAccess *bool,
) error {
	ctx, span := h.obsv.Tracer.Start(ctx, "events.Handler.onPullRequestCommentCreated")
	defer span.End()

	pr := actx.PullRequest
	logger := h.obsv.LoggerWithTelemetry(ctx)

	_, isAgentAuthoredPR := h.appProvider.IsAgenticActor(pr.Author)
	if isAgentAuthoredPR {
		logger.Info("processing comment on agent-authored pull request")
	} else {
		logger.Info("processing comment on human-authored pull request")
	}

	// Comment-level validation (ordered cheapest/most-likely-to-skip first)

	if !commentMentionsAgent {
		logger.Info("Ignoring comment because it does not mention an agent")
		return nil
	}

	if pr.IsClosed() {
		logger.Info("Ignoring comment because pull request is closed")
		return nil
	}

	comment := pr.CommentByID(event.Comment.ID)
	if comment == nil {
		return goerrors.New("failed to get pull request comment")
	}

	if comment.Author.GetID() != event.Actor.ID {
		return goerrors.New("comment author does not match event actor")
	}

	_, isAgentComment := h.appProvider.IsAgenticActor(comment.Author)
	if isAgentComment || comment.Author.IsBot() {
		logger.Info("Ignoring comment because it was authored by an agent or a bot")
		return nil
	}

	if !actx.PermissionsFor(comment.Author).Push {
		logger.Info("Ignoring comment because actor does not have write access to the repo")
		return nil
	}

	// Determine execution mode: work on current branch or create stacked PR
	createStackedPR := h.shouldCreateStackedPR(ctx, comment.Body, event.Actor.ID, event.Comment.ID, "comment")

	logger.Info("Comment is actionable, proceeding",
		kvp.Bool("is_agent_authored_pr", isAgentAuthoredPR),
		kvp.Bool("create_stacked_pr", createStackedPR))

	// Acknowledge the comment with a 👀 reaction
	if err := comment.AddReaction(ctx, gh, github.GQLReactionContentEyes); err != nil {
		// Bummer, but we don't want to fail the job
		h.obsv.LogAndReportError(ctx, err, "failed to add reaction")
	}

	// Execute the determined action
	if createStackedPR {
		h.obsv.Increment(ctx, "events.on_pull_request_comment.create_stacked_pr", stats.Tags{
			"is_agent_authored_pr": fmt.Sprintf("%t", isAgentAuthoredPR),
		})
		return h.buildAndQueueStackedPRJob(ctx, gh, actx, event, app, requestedModel, appWorkflowsAccess)
	}

	h.obsv.Increment(ctx, "events.on_pull_request_comment.work_on_current_branch", stats.Tags{
		"is_agent_authored_pr": fmt.Sprintf("%t", isAgentAuthoredPR),
	})
	return h.buildAndQueueCurrentBranchJob(ctx, gh, assignment, actx, event, isAgentAuthoredPR, app, requestedModel, appWorkflowsAccess)
}

// buildAndQueueCurrentBranchJob creates and queues a job that works on the PR's
// existing branch. Used for both agent-authored and human-authored PRs when the
// decision is to work on the current branch.
func (h *Handler) buildAndQueueCurrentBranchJob(
	ctx context.Context,
	gh github.ClientInterface,
	assignment *jobs.Assignment,
	actx *github.PullRequestContext,
	event PullRequestCommentCreatedEvent,
	isAgentAuthoredPR bool,
	app sweagentd.AgenticApp,
	requestedModel string,
	appWorkflowsAccess *bool,
) error {
	ctx, span := h.obsv.Tracer.Start(ctx, "events.Handler.buildAndQueueCurrentBranchJob")
	defer span.End()

	pr := actx.PullRequest
	repo := actx.Repository
	owner := repo.Owner
	comment := pr.CommentByID(event.Comment.ID)

	ggRepo, err := gh.GetRepositoryByID(ctx, repo.ID)
	if err != nil {
		return goerrors.Errorf("failed to get repository: %w", err)
	}

	// Pre-flight check: verify repository rules (rulesets and classic branch protection)
	err = h.validateRules(ctx, gh, app, assignment, event.Actor, repo, &pr)
	if err != nil {
		return err
	}

	var allJobs []*jobs.Job
	var pendingJob *jobs.Job

	if assignment != nil {
		allJobs, pendingJob, err = jobutils.JobsForAssignment(ctx, h.obsv, h.jobService, gh, h.ffClient, assignment, ggRepo)
		if err != nil {
			return goerrors.Errorf("failed to get jobs for assignment: %w", err)
		}
	}

	actor, err := h.getJobActor(ctx, event.Actor)
	if err != nil {
		return goerrors.Errorf("failed to get job actor: %w", err)
	}

	mostRecentJob := getMostRecentJobWithAgent(allJobs, app.AppID())
	if mostRecentJob != nil {
		h.obsv.LoggerWithTelemetry(ctx).Info("using agent-scoped most recent job for model inheritance",
			kvp.Int64("agent_id", app.AppID()),
			kvp.String("most_recent_job_id", mostRecentJob.ID),
			kvp.String("most_recent_job_model", mostRecentJob.Model))
	}

	var builder *jobservice.JobBuilderWithAssignmentAndActor

	if pendingJob == nil {
		baseBuilder := h.jobService.NewJobBuilder(jobs.AgentActionFixPRComment, ggRepo, pr.HeadRef.Name)

		if assignment == nil {
			// Create new assignment for PRs working on current branch without an existing assignment
			useAsyncSessions := h.ffClient.IsEnabledForUserOrRepo(ctx, featureflags.CopilotSWEAgentUseAsyncSessions, actor.ID, repo.ID)
			builder = baseBuilder.
				WithNewAssignment(owner.GetID(), repo.ID, owner.NodeID, repo.NodeID, owner.Login, repo.Name, useAsyncSessions, pullRequestResource(pr.GetID())).
				WithAssignmentPullRequest(pr.GetID(), pr.Number).
				WithJobActor(*actor)
		} else {
			builder = baseBuilder.
				ForAssignment(assignment).
				WithAssignmentPullRequest(pr.GetID(), pr.Number).
				WithJobActor(*actor)
		}
	} else {
		builder = h.jobService.
			JobBuilderForJob(assignment, pendingJob, ggRepo).
			WithJobActor(*actor)
		builder.WithAssignmentPullRequest(pr.GetID(), pr.Number)
	}

	eventType := jobs.EventTypePullRequestComment
	if !isAgentAuthoredPR {
		eventType = jobs.EventTypePullRequestCommentNonCopilotPullRequest
	}

	builder = builder.
		WithModel(requestedModel).
		WithRequestStartedAt(event.Timestamp).
		WithJobInitHook(func(j *jobs.Job) {
			// Priority for model selection:
			// 1. Explicit model from mention (e.g., "@copilot+claude-opus.4.5") via JobBuilder.WithModel/DetermineModel
			// 2. Inherited model from most recent job
			// 3. Auto model selection
			if shouldInheritModel(assignment, mostRecentJob, requestedModel) {
				// Inherit the most recent model used in prior jobs for this PR. This takes precedence over any
				// auto model selection.
				j.Model = mostRecentJob.Model
				j.IsAutoMode = false
			}
			j.BranchName = pr.HeadRef.Name
			j.PullRequestID = pr.GetID()
			j.PullRequestNumber = pr.Number
			// Make sure this comment is added to the pending job so the LLM considers it
			j.CommentIDs = append(j.CommentIDs, comment.GetID())
			// Add all other (qualifying) comments and reviews that haven't been included on a job yet.
			jobutils.AddUnprocessedCommentsAndReviewsToJob(gh, actx, allJobs, j, h.appProvider.IsAgenticActor)
		}).
		WithEvent(jobservice.Event{
			Type:        eventType,
			URL:         event.EventUrl,
			Identifiers: []string{fmt.Sprintf("%d", comment.GetID())},
		}).
		WithProblemStatementBuilder(func(c context.Context, j *jobs.Job) (jobs.ProblemStatement, error) {
			return problemstatement.NewPullRequestBuilder(h.obsv, actx, j, githubtwirp.NewAuthorResolver(h.obsv, h.ghTwirp, h.ffClient), h.appProvider).Build(c)
		}).
		WithAgentID(app.AppID()).
		WithWorkflowsAccess(cmp.Or(appWorkflowsAccess, jobs.InheritedWorkflowsAccess(allJobs, app.AppID())))

	// Track assignment modifications when working on a PR the agent doesn't own.
	// For agent-authored PRs this is the natural behavior and doesn't need tracking.
	if !isAgentAuthoredPR {
		builder = builder.WithRespectAssignmentModified()
	}

	if has, runningJobID := jobs.HasQueuedOrRunningJobs(allJobs); has {
		h.obsv.LoggerWithTelemetry(ctx).Info("Job pending but not launching agent because there is another job in progress",
			kvp.String("running_job_id", runningJobID))

		_, _, err = builder.Build(ctx, gh)
		if err != nil {
			return goerrors.Errorf("failed to build job: %w", err)
		}
		return nil
	}

	_, pendingJob, err = builder.WithNewSession().WithAINameGen().Build(ctx, gh)
	if err != nil {
		return goerrors.Errorf("failed to build job: %w", err)
	}

	h.obsv.LoggerWithTelemetry(ctx).Info("Queuing new job for pull request (current branch)")

	_, err = h.jobService.QueueJobForExecution(ctx, pendingJob)
	if err != nil {
		return goerrors.Errorf("failed to queue job: %w", err)
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

// buildAndQueueStackedPRJob creates and queues a job that opens a new stacked PR
// branched off the current PR's head. Used when the user explicitly requests a new
// PR or when legacy behavior defaults to creating stacked PRs for human-authored PRs.
func (h *Handler) buildAndQueueStackedPRJob(ctx context.Context, gh github.ClientInterface, actx *github.PullRequestContext, event PullRequestCommentCreatedEvent, app sweagentd.AgenticApp, requestedModel string, appWorkflowsAccess *bool) error {
	ctx, span := h.obsv.Tracer.Start(ctx, "events.Handler.buildAndQueueStackedPRJob")
	defer span.End()

	pr := actx.PullRequest
	repo := actx.Repository
	owner := repo.Owner

	h.obsv.LoggerWithTelemetry(ctx).Info("Building stacked PR job")

	jobActor, err := h.getJobActor(ctx, event.Actor)
	if err != nil {
		return goerrors.Errorf("failed to get job actor: %w", err)
	}

	comment := pr.CommentByID(event.Comment.ID)
	if comment == nil {
		return goerrors.New("failed to get pull request comment")
	}

	ggRepo, err := gh.GetRepositoryByID(ctx, repo.ID)
	if err != nil {
		return goerrors.Errorf("failed to get repository: %w", err)
	}

	useAsyncSessions := h.ffClient.IsEnabledForUserOrRepo(ctx, featureflags.CopilotSWEAgentUseAsyncSessions, jobActor.ID, repo.ID)

	_, job, err := h.jobService.
		NewJobBuilder(jobs.AgentActionFixPRComment, ggRepo, pr.HeadRef.Name).
		WithNewAssignment(owner.GetID(), repo.ID, owner.NodeID, repo.NodeID, owner.Login, repo.Name, useAsyncSessions, pullRequestResource(pr.GetID())).
		WithJobActor(*jobActor).
		WithRequestStartedAt(event.Timestamp).
		WithModel(requestedModel). // no-op if empty, routes through DetermineModel validation
		// Importantly, the `actx` is still for the original PR, which is what we want
		// since we want the problem statement to reflect the full context of the original PR
		// and the comment that triggered the stacked PR creation.
		WithProblemStatementBuilder(func(c context.Context, j *jobs.Job) (jobs.ProblemStatement, error) {
			return problemstatement.NewPullRequestBuilder(h.obsv, actx, j, githubtwirp.NewAuthorResolver(h.obsv, h.ghTwirp, h.ffClient), h.appProvider).Build(c)
		}).
		WithJobInitHook(func(j *jobs.Job) {
			// Make sure this comment is added to the job so the LLM considers it
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
		WithWorkflowsAccess(appWorkflowsAccess).
		WithNewSession().
		WithAINameGen().
		Build(ctx, gh)
	if err != nil {
		return goerrors.Errorf("failed to build job: %w", err)
	}

	h.obsv.LoggerWithTelemetry(ctx).Info("Queuing new job for stacked PR")

	_, err = h.jobService.QueueJobForExecution(ctx, job)
	if err != nil {
		return goerrors.Errorf("failed to queue job: %w", err)
	}

	// Comment on the original PR to let the user know where the work is happening
	commentBody := fmt.Sprintf("@%s I've opened a new pull request, #%d, to work on those changes. Once the pull request is ready, I'll request review from you.", jobActor.DisplayLogin, job.PullRequestNumber)
	if _, err := gh.CreateComment(ctx, int64(repo.ID), pr.Number, commentBody); err != nil {
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

	return h.fillJobActorDetails(ctx, jobActor)
}

// fillJobActorDetails populates missing display login and tracking ID on a
// JobActor by querying GitHub APIs. This is shared by getJobActor (hydro event
// actors), getJobActorFromGitHubUser (GitHub API user objects), and automation
// owner attribution.
func (h *Handler) fillJobActorDetails(ctx context.Context, jobActor *jobs.JobActor) (*jobs.JobActor, error) {
	if jobActor.DisplayLogin == "" {
		err := jobActor.FillDisplayLogin(ctx, h.obsv, h.ffClient, h.ghTwirp, uint64(jobActor.ID))
		if err != nil {
			return nil, goerrors.Errorf("failed to fill display login for job actor: %w", err)
		}
	}

	if jobActor.TrackingID == "" {
		userDetails, err := h.ghTwirp.GetCopilotUserDetails(ctx, jobActor.ID)
		if err != nil {
			h.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to get copilot user for tracking ID")
		} else {
			jobActor.TrackingID = userDetails.AnalyticsTrackingId
		}
	}

	return jobActor, nil
}
