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
	"github.com/github/sweagentd/internal/sweagentd"
)

func reviewMentionsAgenticActor(review PullRequestReviewSubmitEvent, isAgenticMention func(string) (sweagentd.AgenticApp, bool)) bool {
	if _, ok := isAgenticMention(review.PullRequestReview.Body); ok {
		return true
	}

	for _, comment := range review.PullRequestReview.Comments {
		if _, ok := isAgenticMention(comment); ok {
			return true
		}
	}

	return false
}

func (h *Handler) OnPullRequestReviewSubmit(ctx context.Context, event PullRequestReviewSubmitEvent) error {
	assignment, err := h.assignmentForPR(ctx, &event, &event.PullRequest.ID, &event.PullRequest.Number)
	if err != nil {
		return goerrors.Errorf("failed to get assignment for pull request: %w", err)
	}

	app, err := h.appProvider.FindByID(ctx, event.AgentID)
	if err != nil {
		return goerrors.Errorf("failed to find app by ID from review: %w", err)
	}

	reviewMentionsAgent := reviewMentionsAgenticActor(event, h.appProvider.IsAgenticMention)

	if assignment == nil && !reviewMentionsAgent {
		h.obsv.LoggerWithTelemetry(ctx).Info("No assignment found for pull request and review does not mention agent")
		return nil
	}

	ignore, err := h.ShouldIgnorePRCommentOrReview(ctx, event.PullRequest, event.Actor)
	if err != nil {
		return goerrors.Errorf("failed to check if review should be ignored: %w", err)
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
			h.obsv.LoggerWithTelemetry(ctx).Info("Ignoring review because originating GitHub App lacks contents:write",
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
		h.obsv.LoggerWithTelemetry(ctx).Info("Ignoring review because it is on a cross-repository pull request")
		return nil
	}

	h.setCtxPullRequestID(ctx, actx.PullRequest.GetID(), actx.PullRequest.Number)

	h.obsv.Increment(ctx, "events.on_pull_request_review_submit.handled", nil)

	// Process the review: validate, determine action (stacked PR vs current branch), and execute.
	// Pass the webhook-based mention detection result so the wake logic can use it as a fallback
	// when GraphQL-based mention detection (mentionsCopilot) misses mentions due to eventual
	// consistency or pagination limits.
	err = h.onPullRequestReviewSubmit(ctx, gh, assignment, actx, event, app, reviewMentionsAgent, appWorkflowsAccess)
	return h.handlePRReviewError(ctx, err, assignment, event.Actor.Login, event)
}

// handlePRReviewError translates specific error types from onPullRequestReviewSubmit into
// appropriate responses (e.g., user-facing error comments on the PR).
func (h *Handler) handlePRReviewError(ctx context.Context, err error, assignment *jobs.Assignment, actorLogin string, event PullRequestReviewSubmitEvent) error {
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
	// TODO: (colbylwilliams) determine if we still need this
	return jobutils.NewUnhandledErrorWithPRComment(ctx, err, assignment, actorLogin)
}

// onPullRequestReviewSubmit validates the review, determines whether to work on the current
// branch or create a stacked PR, and dispatches to the appropriate job builder.
//
// This is the unified entry point for both agent-authored and human-authored PRs.
// The decision of stacked PR vs current branch is made once in shouldCreateStackedPRForReview.
func (h *Handler) onPullRequestReviewSubmit(
	ctx context.Context,
	gh github.ClientInterface,
	assignment *jobs.Assignment,
	actx *github.PullRequestContext,
	event PullRequestReviewSubmitEvent,
	app sweagentd.AgenticApp,
	eventMentionsAgent bool,
	appWorkflowsAccess *bool,
) error {
	ctx, span := h.obsv.Tracer.Start(ctx, "events.Handler.onPullRequestReviewSubmit")
	defer span.End()

	pr := actx.PullRequest
	logger := h.obsv.LoggerWithTelemetry(ctx)

	authorApp, isAgentAuthoredPR := h.appProvider.IsAgenticActor(pr.Author)
	if isAgentAuthoredPR {
		logger.Info("processing review on agent-authored pull request")
	} else {
		logger.Info("processing review on human-authored pull request")
	}

	// Review-level validation (ordered cheapest/most-likely-to-skip first)

	// 1. Field check on already-fetched PR — free
	if pr.IsClosed() {
		logger.Info("Ignoring review because pull request is closed")
		return nil
	}

	// 2. Local lookup in in-memory review list
	review := pr.ReviewByID(event.PullRequestReview.ID)
	if review == nil {
		return goerrors.New("failed to get pull request review")
	}

	// 3. Int comparison — free
	if review.Author.GetID() != event.Actor.ID {
		return goerrors.New("review author does not match event actor")
	}

	// 4. In-memory actor list check + field check — free
	_, isAgentReviewAuthor := h.appProvider.IsAgenticActor(review.Author)
	if isAgentReviewAuthor || review.Author.IsBot() {
		logger.Info("Ignoring review because it was authored by an agent or a bot")
		return nil
	}

	// 5. Lookup in already-fetched PullRequestContext participants — free (no API call)
	if !actx.PermissionsFor(review.Author).Push {
		logger.Info("Ignoring review because actor does not have write access to the repo")
		return nil
	}

	// 6. Field checks — free
	if review.Approved() && review.Comments.Len() == 0 {
		logger.Info("Ignoring review because it is an approval with no comments")
		return nil
	}

	// 7. Wake logic: review mentions agent OR changes-requested by assignee.
	// We check both the GraphQL-based mention detection (mentionsCopilot) and the webhook
	// event-based detection (eventMentionsAgent) because the GraphQL data may not yet reflect
	// the just-submitted review due to eventual consistency or pagination limits.
	mentionsCopilot := h.mentionsCopilot(review)
	shouldWake := len(mentionsCopilot) > 0 || eventMentionsAgent

	if !shouldWake {
		isAssignee := false
		for _, assignee := range pr.Assignees.Nodes {
			if assignee.GetID() == review.Author.GetID() {
				isAssignee = true
				break
			}
		}

		// Wake up if review requests changes AND reviewer is an assignee
		if review.ChangesRequested() && isAssignee {
			if authorApp != nil {
				app = authorApp
			}
			shouldWake = true
		}
	}

	if !shouldWake {
		logger.Info("Ignoring review because it does not mention agent and is not a 'Request changes' from an assignee")
		return nil
	}

	// Determine execution mode: work on current branch or create stacked PR
	createStackedPR := h.shouldCreateStackedPR(ctx, collectReviewText(review), event.Actor.ID, event.PullRequestReview.ID, "review")

	logger.Info("Review is actionable, proceeding",
		kvp.Bool("is_agent_authored_pr", isAgentAuthoredPR),
		kvp.Bool("create_stacked_pr", createStackedPR))

	// Acknowledge the review with 👀 reactions
	jobutils.AddReactionsForReview(ctx, h.obsv, gh, review)

	// Execute the determined action
	if createStackedPR {
		h.obsv.Increment(ctx, "events.on_pull_request_review.create_stacked_pr", stats.Tags{
			"is_agent_authored_pr": fmt.Sprintf("%t", isAgentAuthoredPR),
		})
		return h.buildAndQueueStackedPRReviewJob(ctx, gh, actx, event, app, review, appWorkflowsAccess)
	}

	h.obsv.Increment(ctx, "events.on_pull_request_review.work_on_current_branch", stats.Tags{
		"is_agent_authored_pr": fmt.Sprintf("%t", isAgentAuthoredPR),
	})
	return h.buildAndQueueCurrentBranchReviewJob(ctx, gh, assignment, actx, event, isAgentAuthoredPR, app, review, appWorkflowsAccess)
}

// collectReviewText combines the review body and all inline comment bodies into
// a single string for intent detection.
func collectReviewText(review *github.GQLPullRequestReview) string {
	var b strings.Builder
	if review.GetBody() != "" {
		b.WriteString(review.GetBody())
	}
	for _, comment := range review.Comments.Nodes {
		if comment.GetBody() != "" {
			if b.Len() > 0 {
				b.WriteString("\n")
			}
			b.WriteString(comment.GetBody())
		}
	}
	return b.String()
}

// buildAndQueueCurrentBranchReviewJob creates and queues a job that works on the PR's
// existing branch in response to a review. Used for both agent-authored and human-authored
// PRs when the decision is to work on the current branch.
func (h *Handler) buildAndQueueCurrentBranchReviewJob(
	ctx context.Context,
	gh github.ClientInterface,
	assignment *jobs.Assignment,
	actx *github.PullRequestContext,
	event PullRequestReviewSubmitEvent,
	isAgentAuthoredPR bool,
	app sweagentd.AgenticApp,
	review *github.GQLPullRequestReview,
	appWorkflowsAccess *bool,
) error {
	ctx, span := h.obsv.Tracer.Start(ctx, "events.Handler.buildAndQueueCurrentBranchReviewJob")
	defer span.End()

	pr := actx.PullRequest
	repo := actx.Repository
	owner := repo.Owner

	var allJobs []*jobs.Job
	var pendingJob *jobs.Job
	var err error

	ggRepo, err := gh.GetRepositoryByID(ctx, repo.ID)
	if err != nil {
		return goerrors.Errorf("failed to get repository: %w", err)
	}

	// Pre-flight check: verify repository rules (rulesets and classic branch protection)
	err = h.validateRules(ctx, gh, app, assignment, event.Actor, repo, &pr)
	if err != nil {
		return err
	}

	if assignment != nil {
		assignmentRepo := ggRepo
		if assignment.RepoID != repo.ID {
			assignmentRepo, err = gh.GetRepositoryByID(ctx, assignment.RepoID)
			if err != nil {
				return goerrors.Errorf("failed to get repository associated with assignment: %w", err)
			}
		}

		allJobs, pendingJob, err = jobutils.JobsForAssignment(ctx, h.obsv, h.jobService, gh, h.ffClient, assignment, assignmentRepo)
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

	eventType := jobs.EventTypePullRequestReview
	if !isAgentAuthoredPR {
		eventType = jobs.EventTypePullRequestReviewNonCopilotPullRequest
	}

	builder = builder.
		WithRequestStartedAt(event.Timestamp).
		WithJobInitHook(func(j *jobs.Job) {
			// TODO (@dy-hu): Add model picker support for PR reviews and pass requestedModel here
			if shouldInheritModel(assignment, mostRecentJob, "") {
				j.Model = mostRecentJob.Model
				j.IsAutoMode = false
			}
			j.BranchName = pr.HeadRef.Name
			j.PullRequestID = pr.GetID()
			j.PullRequestNumber = pr.Number
			j.ReviewIDs = append(j.ReviewIDs, review.GetID())
			jobutils.AddUnprocessedCommentsAndReviewsToJob(gh, actx, allJobs, j, h.appProvider.IsAgenticActor)
		}).
		WithEvent(jobservice.Event{
			Type:        eventType,
			URL:         event.EventUrl,
			Identifiers: []string{fmt.Sprintf("%d", review.GetID())},
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

	h.obsv.LoggerWithTelemetry(ctx).Info("Queuing new job for pull request review (current branch)")

	_, err = h.jobService.QueueJobForExecution(ctx, pendingJob)
	if err != nil {
		return goerrors.Errorf("failed to queue job: %w", err)
	}

	return nil
}

func (h *Handler) mentionsCopilot(review *github.GQLPullRequestReview) []github.ReviewOrReviewComment {
	return reviewsWithCopilotMention(review, h.appProvider.IsAgenticMention)
}

func reviewsWithCopilotMention(review *github.GQLPullRequestReview, mentionChecker func(string) (sweagentd.AgenticApp, bool)) []github.ReviewOrReviewComment {
	var reviews []github.ReviewOrReviewComment

	// If the main body mentions Copilot, we can return early
	if _, ok := mentionChecker(review.GetBody()); ok {
		return []github.ReviewOrReviewComment{review}
	}

	for _, comment := range review.Comments.Nodes {
		if _, ok := mentionChecker(comment.GetBody()); ok {
			reviews = append(reviews, &comment)
		}
	}

	return reviews
}

// buildAndQueueStackedPRReviewJob creates and queues a job that opens a new stacked PR
// branched off the current PR's head in response to a review. Used when the user explicitly
// requests a new PR or when legacy behavior defaults to creating stacked PRs for
// human-authored PRs.
func (h *Handler) buildAndQueueStackedPRReviewJob(
	ctx context.Context,
	gh github.ClientInterface,
	actx *github.PullRequestContext,
	event PullRequestReviewSubmitEvent,
	app sweagentd.AgenticApp,
	review *github.GQLPullRequestReview,
	appWorkflowsAccess *bool,
) error {
	ctx, span := h.obsv.Tracer.Start(ctx, "events.Handler.buildAndQueueStackedPRReviewJob")
	defer span.End()

	pr := actx.PullRequest
	repo := actx.Repository
	owner := repo.Owner

	h.obsv.LoggerWithTelemetry(ctx).Info("Building stacked PR job for review")

	actor, err := h.getJobActor(ctx, event.Actor)
	if err != nil {
		return goerrors.Errorf("failed to get job actor: %w", err)
	}

	ggRepo, err := gh.GetRepositoryByID(ctx, repo.ID)
	if err != nil {
		return goerrors.Errorf("failed to get repository: %w", err)
	}

	useAsyncSessions := h.ffClient.IsEnabledForUserOrRepo(ctx, featureflags.CopilotSWEAgentUseAsyncSessions, actor.ID, repo.ID)

	_, job, err := h.jobService.
		NewJobBuilder(jobs.AgentActionFixPRComment, ggRepo, pr.HeadRef.Name).
		WithNewAssignment(owner.GetID(), repo.ID, owner.NodeID, repo.NodeID, owner.Login, repo.Name, useAsyncSessions, pullRequestResource(pr.GetID())).
		WithJobActor(*actor).
		WithRequestStartedAt(event.Timestamp).
		WithProblemStatementBuilder(func(c context.Context, j *jobs.Job) (jobs.ProblemStatement, error) {
			return problemstatement.NewReviewBuilder(h.obsv, actx, j, review.GetID(), githubtwirp.NewAuthorResolver(h.obsv, h.ghTwirp, h.ffClient), h.appProvider).Build(c)
		}).
		WithJobInitHook(func(j *jobs.Job) {
			j.ReviewIDs = append(j.ReviewIDs, review.GetID())
		}).
		WithEvent(jobservice.Event{
			Type:        jobs.EventTypePullRequestReviewNonCopilotPullRequest,
			URL:         event.EventUrl,
			Identifiers: eventIdentifiers(review.GetID()),
		}).
		WithFeaturesBuilder(func(c context.Context, j *jobs.Job) jobs.EnvironmentFeatures {
			body := h.generateReviewStackBodyBase(review)

			title, err := h.generateStackPRTitle(c, j, pr.Title, body)
			if err != nil {
				h.obsv.LogAndReportError(c, err, "failed to generate stack PR title")
				title = fmt.Sprintf("[WIP] Make requested changes to #%d", pr.Number)
			}

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

	h.obsv.LoggerWithTelemetry(ctx).Info("Queuing new job for stacked PR (review)")

	_, err = h.jobService.QueueJobForExecution(ctx, job)
	if err != nil {
		return goerrors.Errorf("failed to queue job: %w", err)
	}

	// Comment on the original PR to let the user know where the work is happening
	commentBody := fmt.Sprintf("@%s I've opened a new pull request, #%d, to work on those changes. Once the pull request is ready, I'll request review from you.", actor.DisplayLogin, job.PullRequestNumber)

	// Check where the @copilot mention actually is, and reply in the correct place for better context and threading.
	reviewsWithCopilotMentions := h.mentionsCopilot(review)
	if h.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentReplyToCommentMentionsOnNonCopilotPRs, job) && len(reviewsWithCopilotMentions) == 1 {
		repoInfo, err := gh.GetRepositoryByID(ctx, job.RepoID)
		if err != nil {
			h.obsv.LogAndReportError(ctx, err, "failed to get repository for job")
		} else {
			if reviewComment, ok := reviewsWithCopilotMentions[0].(*github.GQLPullRequestReviewComment); ok {
				if _, err := gh.CreateCommentInReplyTo(ctx, repoInfo.Owner.GetLogin(), repoInfo.GetName(), pr.Number, commentBody, reviewComment.GetID()); err != nil {
					h.obsv.LogAndReportError(ctx, err, "failed to comment in reply to original review comment")
				}
			} else {
				if _, err := gh.CreateComment(ctx, int64(repo.ID), pr.Number, commentBody); err != nil {
					h.obsv.LogAndReportError(ctx, err, "failed to comment on original PR")
				}
			}
		}
	} else {
		if _, err := gh.CreateComment(ctx, int64(repo.ID), pr.Number, commentBody); err != nil {
			h.obsv.LogAndReportError(ctx, err, "failed to comment on original PR")
		}
	}

	return nil
}

func (h *Handler) generateReviewStackBodyBase(review *github.GQLPullRequestReview) string {
	reviewsWithCopilotMentions := h.mentionsCopilot(review)

	// If only the top-level review mentioned Copilot, we can link to that review directly
	// At this point we've already confirmed that at least one review/comment mentioned Copilot
	var body string
	if len(reviewsWithCopilotMentions) == 1 {
		r := reviewsWithCopilotMentions[0]
		body = fmt.Sprintf("Triggering review: %s\n> %s", r.GetURL(), strings.ReplaceAll(r.GetBody(), "\n", "\n> "))
	} else {
		body = "Triggering reviews:"
		for _, r := range reviewsWithCopilotMentions {
			body += fmt.Sprintf("\n- %s\n> %s", r.GetURL(), strings.ReplaceAll(r.GetBody(), "\n", "\n> "))
		}
	}

	return body
}
