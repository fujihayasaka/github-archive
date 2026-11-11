package events

import (
	"context"
	"fmt"
	"strings"

	"github.com/github/github-telemetry-go/kvp"
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
	assignment, err := h.assignmentForPR(ctx, event.Repo.OwnerID, event.Repo.ID, &event.PullRequest.ID, &event.PullRequest.Number)
	if err != nil {
		return fmt.Errorf("failed to get assignment for pull request: %w", err)
	}

	appFromReview, err := h.appProvider.FindByID(event.AgentID)
	if err != nil {
		return fmt.Errorf("failed to find app by ID from review: %w", err)
	}

	reviewMentionsAgenticActor := reviewMentionsAgenticActor(event, h.appProvider.IsAgenticMention)

	if assignment == nil && !reviewMentionsAgenticActor {
		h.obsv.LoggerWithTelemetry(ctx).Info("No assignment found for pull request and not opening stacked PR, skipping review processing")
		return nil
	}

	ignore, err := h.ShouldIgnorePRCommentOrReview(ctx, event.PullRequest, event.Actor)
	if err != nil {
		return fmt.Errorf("failed to check if comment should be ignored: %w", err)
	}
	if ignore {
		return nil
	}

	h.obsv.Statter.Counter("events.on_pull_request_review_submit.handled", nil, 1)

	gh, err := h.ghFactory.NewClientForRepo(ctx, appFromReview, &event)
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
		h.obsv.LoggerWithTelemetry(ctx).Info("Ignoring review because it is on a cross-repository pull request")
		return nil
	}

	h.setCtxPullRequestID(ctx, actx.PullRequest.GetID(), actx.PullRequest.Number)

	// The user left a review on a non-Agentic PR, @-mentioning Agentic.
	_, isAgenticAuthor := h.appProvider.IsAgenticActor(actx.PullRequest.Author)
	if reviewMentionsAgenticActor && !isAgenticAuthor {
		h.obsv.Increment(ctx, "events.handle_review_on_non_copilot_authored_pr", nil)
		err = h.handleReviewOnNonCopilotAuthoredPullRequest(ctx, gh, assignment, actx, event, appFromReview)
		if err != nil && jobservice.IsBuilderFinalizedJobError(err) {
			return nil
		}
		return err
	}

	err = h.onPullRequestReviewSubmit(ctx, gh, assignment, actx, event, appFromReview)
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

func (h *Handler) onPullRequestReviewSubmit(
	ctx context.Context, gh github.ClientInterface, assignment *jobs.Assignment, actx *github.PullRequestContext, event PullRequestReviewSubmitEvent, app sweagentd.AgenticApp,
) error {
	ctx, span := h.obsv.Tracer.Start(ctx, "events.Handler.onPullRequestReviewSubmit")
	defer span.End()

	pr := actx.PullRequest
	repo := actx.Repository
	owner := repo.Owner

	logger := h.obsv.LoggerWithTelemetry(ctx)

	logger.Info("processing pull request review")

	review := pr.ReviewByID(event.PullRequestReview.ID)
	if review == nil {
		return fmt.Errorf("failed to get pull request review")
	}

	// Double check that the review author matches the event actor
	if review.Author.GetID() != event.Actor.ID {
		return fmt.Errorf("review author does not match event actor")
	}

	// Ignore events for closed PRs
	if pr.IsClosed() {
		logger.Info("Ignoring review because pull request is closed")
		return nil
	}

	// Ignore events for PRs not authored by Agentic (unless WorkOnCurrentBranch FF is enabled)
	authorApp, isAgenticPRAuthor := h.appProvider.IsAgenticActor(pr.Author)
	if !isAgenticPRAuthor && !h.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentWorkOnCurrentBranch, &event) {
		logger.Info("Ignoring review because pull request is not authored by Agentic")
		return nil
	}

	// Ignore reviews authored by Agentic or other bots
	_, isAgenticReviewAuthor := h.appProvider.IsAgenticActor(review.Author)
	if isAgenticReviewAuthor || review.Author.IsBot() {
		logger.Info("Ignoring review because it was authored by Agentic or a bot")
		return nil
	}

	// Only process events where the actor has write access to the repo
	if !actx.PermissionsFor(review.Author).Push {
		logger.Info("Ignoring review because actor does not have write access to the repo")
		return nil
	}

	// Skip if the review is an approval with no comments.
	if review.Approved() && review.Comments.Len() == 0 {
		logger.Info("Ignoring review because it is an approval with no comments")
		return nil
	}

	mentionsCopilot := h.mentionsCopilot(review)
	shouldWake := len(mentionsCopilot) > 0

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
			app = authorApp
			shouldWake = true
		}
	}

	if !shouldWake {
		logger.Info("Ignoring review because it does not mention Copilot and is not a 'Request changes' from an assignee")
		return nil
	}

	logger.Info("Waking up Copilot because new feedback is actionable")

	// ✅ All validation/permission checks passed, now we start doing things

	// Add a 👀 reaction to acknowledge the review
	jobutils.AddReactionsForReview(ctx, h.obsv, gh, review)

	var allJobs []*jobs.Job
	var pendingJob *jobs.Job

	if assignment != nil {
		repo, err := gh.GetRepositoryByID(ctx, assignment.RepoID)
		if err != nil {
			return goerrors.Errorf("failed to get repository associated with assignment: %w", err)
		}

		allJobs, pendingJob, err = jobutils.JobsForAssignment(ctx, h.obsv, h.jobService, gh, h.ffClient, assignment, repo)
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

	// Fetch repository information from GitHub API
	ggRepo, err := gh.GetRepositoryByID(ctx, repo.ID)
	if err != nil {
		return goerrors.Errorf("failed to get repository: %w", err)
	}

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
		WithJobInitHook(func(j *jobs.Job) {
			// TODO (@dy-hu): Add model picker support for PR reviews (same as PR comments) and pass requestedModel here
			if shouldInheritModel(assignment, mostRecentJob, "") {
				// Inherit the most recent model used in prior jobs for this PR. This takes precedence over any
				// auto model selection.
				j.Model = mostRecentJob.Model
			}
			j.BranchName = pr.HeadRef.Name
			// Make sure this review is added to the pending job so the LLM considers it
			j.ReviewIDs = append(j.ReviewIDs, review.GetID())
			// Add all other (qualifying) comments and reviews that haven't been included on a job yet.
			jobutils.AddUnprocessedCommentsAndReviewsToJob(gh, actx, allJobs, j, h.appProvider.IsAgenticActor)
		}).
		WithEvent(jobservice.Event{
			Type:        jobs.EventTypePullRequestReview,
			URL:         event.EventUrl,
			Identifiers: []string{fmt.Sprintf("%d", review.GetID())},
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

func (h *Handler) handleReviewOnNonCopilotAuthoredPullRequest(ctx context.Context, gh github.ClientInterface, assignment *jobs.Assignment, actx *github.PullRequestContext, event PullRequestReviewSubmitEvent, app sweagentd.AgenticApp) error {
	ctx, span := h.obsv.Tracer.Start(ctx, "events.Handler.handleReviewOnNonCopilotAuthoredPullRequest")
	defer span.End()
	if h.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentWorkOnCurrentBranch, &event) {
		return h.createReviewJobOnCurrentBranch(ctx, gh, assignment, actx, event, app)
	}
	return h.createReviewJobWithStackedPR(ctx, gh, actx, event, app)
}

func (h *Handler) createReviewJobOnCurrentBranch(ctx context.Context, gh github.ClientInterface, assignment *jobs.Assignment, actx *github.PullRequestContext, event PullRequestReviewSubmitEvent, app sweagentd.AgenticApp) error {
	ctx, span := h.obsv.Tracer.Start(ctx, "events.Handler.createReviewJobOnCurrentBranch")
	defer span.End()

	h.obsv.Increment(ctx, "events.handle_review_on_non_copilot_authored_pr.work_on_current_branch", nil)
	h.obsv.LoggerWithTelemetry(ctx).Info("Handling review on non-Copilot-authored PR by working on current branch")

	return h.onPullRequestReviewSubmit(ctx, gh, assignment, actx, event, app)
}

func (h *Handler) createReviewJobWithStackedPR(ctx context.Context, gh github.ClientInterface, actx *github.PullRequestContext, event PullRequestReviewSubmitEvent, app sweagentd.AgenticApp) error {
	ctx, span := h.obsv.Tracer.Start(ctx, "events.Handler.createReviewJobWithStackedPR")
	defer span.End()

	h.obsv.Increment(ctx, "events.handle_review_on_non_copilot_authored_pr.stacked_pr", nil)
	h.obsv.LoggerWithTelemetry(ctx).Info("Handling review on non-Copilot-authored PR by working with a stacked PR")

	pr := actx.PullRequest
	repo := actx.Repository
	owner := repo.Owner

	logger := h.obsv.LoggerWithTelemetry(ctx)
	logger.Info("processing review on non-Copilot-authored PR to create stacked PR")

	actor, err := h.getJobActor(ctx, event.Actor)
	if err != nil {
		return fmt.Errorf("failed to get job actor: %w", err)
	}

	// Get the review that triggered this event
	review := pr.ReviewByID(event.PullRequestReview.ID)
	if review == nil {
		return fmt.Errorf("failed to get pull request review")
	}

	// Add a 👀 reaction to indicate we've started work
	jobutils.AddReactionsForReview(ctx, h.obsv, gh, review)

	// Fetch repository from GitHub API
	ggRepo, err := gh.GetRepositoryByID(ctx, repo.ID)
	if err != nil {
		return goerrors.Errorf("failed to get repository: %w", err)
	}

	useAsyncSessions := h.ffClient.IsEnabledForUserOrRepo(ctx, featureflags.CopilotSWEAgentUseAsyncSessions, actor.ID, repo.ID)

	_, job, err := h.jobService.
		NewJobBuilder(jobs.AgentActionFixPRComment, ggRepo, pr.HeadRef.Name).
		WithNewAssignment(owner.GetID(), repo.ID, owner.NodeID, repo.NodeID, owner.Login, repo.Name, useAsyncSessions, pullRequestResource(pr.GetID())).
		WithJobActor(*actor).
		WithProblemStatementBuilder(func(c context.Context, j *jobs.Job) (jobs.ProblemStatement, error) {
			// Create problem statement for the stack PR
			// Importantly, the problem statement will focus specifically on the review comments that need
			// to be addressed by Copilot, not the entire PR.
			return problemstatement.NewReviewBuilder(h.obsv, actx, j, review.GetID(), githubtwirp.NewAuthorResolver(h.obsv, h.ghTwirp, h.ffClient), h.appProvider).Build(c)
		}).
		WithJobInitHook(func(j *jobs.Job) {
			// Add the review ID to the job so it gets processed
			j.ReviewIDs = append(j.ReviewIDs, review.GetID())
		}).
		WithEvent(jobservice.Event{
			Type:        jobs.EventTypePullRequestReviewNonCopilotPullRequest,
			URL:         event.EventUrl,
			Identifiers: eventIdentifiers(review.GetID()),
		}).
		WithFeaturesBuilder(func(c context.Context, j *jobs.Job) jobs.EnvironmentFeatures {
			body := h.generateReviewStackBodyBase(review)

			// Generate PR title using CAPI based on the review with the original PR and comment
			title, err := h.generateStackPRTitle(c, j, pr.Title, body)
			if err != nil {
				// Fallback to default title if generation fails
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
	commentBody := fmt.Sprintf("@%s I've opened a new pull request, #%d, to work on those changes. Once the pull request is ready, I'll request review from you.", actor.DisplayLogin, job.PullRequestNumber)

	// Check where the @copilot mention actually is, and reply in the correct place for better context and threading.
	reviewsWithCopilotMentions := h.mentionsCopilot(review)
	if h.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentReplyToCommentMentionsOnNonCopilotPRs, job) && len(reviewsWithCopilotMentions) == 1 {
		// Fetch repository information dynamically
		repoInfo, err := gh.GetRepositoryByID(ctx, job.RepoID)
		if err != nil {
			h.obsv.LogAndReportError(ctx, err, "failed to get repository for job")
		} else {
			// Check if it's a review comment (not the review body)
			if reviewComment, ok := reviewsWithCopilotMentions[0].(*github.GQLPullRequestReviewComment); ok {
				if _, err := gh.CreateCommentInReplyTo(ctx, repoInfo.Owner.GetLogin(), repoInfo.GetName(), pr.Number, commentBody, reviewComment.GetID()); err != nil {
					// Log the error but don't fail the entire operation
					h.obsv.LogAndReportError(ctx, err, "failed to comment in reply to original review comment")
				}
			} else {
				// It's the review body, create a timeline comment
				if _, err := gh.CreateComment(ctx, int64(repo.ID), pr.Number, commentBody); err != nil {
					// Log the error but don't fail the entire operation
					h.obsv.LogAndReportError(ctx, err, "failed to comment on original PR")
				}
			}
		}
	} else {
		// Multiple mentions or no mentions, create a timeline comment
		if _, err := gh.CreateComment(ctx, int64(repo.ID), pr.Number, commentBody); err != nil {
			// Log the error but don't fail the entire operation
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
