package events

import (
	"context"
	"fmt"
	"slices"
	"strings"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobservice"
	"github.com/github/sweagentd/internal/jobutils"
	"github.com/github/sweagentd/internal/limiter"
	"github.com/github/sweagentd/internal/problemstatement"
)

func (h *Handler) OnPullRequestReviewSubmit(ctx context.Context, event PullRequestReviewSubmitEvent) error {
	assignment, err := h.assignmentForPR(ctx, event.Repo.OwnerID, event.Repo.ID, &event.PullRequest.ID, &event.PullRequest.Number)
	if err != nil {
		return fmt.Errorf("failed to get assignment for pull request: %w", err)
	}

	var commentMentionsAgenticActor bool
	if h.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgenticAppsProvider, &event) {
		commentMentionsAgenticActor = h.appProvider.IsAgenticMention(event.PullRequestReview.Body)
		if !commentMentionsAgenticActor {
			if slices.ContainsFunc(event.PullRequestReview.Comments, h.appProvider.IsAgenticMention) {
				commentMentionsAgenticActor = true
			}
		}
	}

	openStackedPR := h.openStackedPR(ctx, &event, event.PullRequestReview, commentMentionsAgenticActor)

	if assignment == nil && !openStackedPR {
		h.obsv.LoggerWithTelemetry(ctx).Info("No assignment found for pull request, skipping review processing")
		return nil
	}

	ignore, err := h.ShouldIgnorePRCommentOrReview(ctx, event.PullRequest, event.Actor)
	if err != nil {
		return fmt.Errorf("failed to check if comment should be ignored: %w", err)
	}
	if ignore {
		return nil
	}

	gh, err := h.ghFactory.NewClientForRepo(ctx, &event)
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

	actx, err := gh.GetPullRequestContext(ctx, event.Repo.NodeID, event.PullRequest.Number)
	if err != nil {
		return fmt.Errorf("failed to get pull request context: %w", err)
	}

	if actx.PullRequest.IsCrossRepository {
		h.obsv.LoggerWithTelemetry(ctx).Info("Ignoring review because it is on a cross-repository pull request")
		return nil
	}

	h.setCtxPullRequestID(ctx, actx.PullRequest.GetID(), actx.PullRequest.Number)

	// The user left a review on a non-Copilot PR, @-mentioning Copilot.
	if openStackedPR && !h.isCopilotActor(ctx, gh, actx.PullRequest.Author) {
		return h.handleReviewOnNonCopilotAuthoredPullRequest(ctx, gh, actx, event)
	}

	err = h.onPullRequestReviewSubmit(ctx, gh, assignment, actx, event)
	if err != nil {
		if limiter.IsAnyLimiterError(err) {
			return err
		}
		// TODO: (colbylwilliams) determine if we still need this
		return jobutils.NewUnhandledErrorWithPRComment(ctx, err, assignment, false, event.Actor.Login)
	}
	return nil
}

func (h *Handler) onPullRequestReviewSubmit(ctx context.Context, gh github.ClientInterface, assignment *jobs.Assignment, actx *github.PullRequestContext, event PullRequestReviewSubmitEvent) error {
	ctx, span := h.obsv.Tracer.Start(ctx, "events.Handler.onPullRequestReviewSubmit")
	defer span.End()

	pr := actx.PullRequest

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

	// Ignore events for closed PRs or PRs not authored by Copilot
	if pr.IsClosed() || !h.isCopilotActor(ctx, gh, pr.Author) {
		logger.Info("Ignoring review because pull request is closed or not authored by Copilot")
		return nil
	}

	// Ignore reviews authored by Copilot or other bots
	if h.isCopilotActor(ctx, gh, review.Author) || review.Author.IsBot() {
		logger.Info("Ignoring review because it was authored by Copilot or a bot")
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

	// Always wake if the review mentions Copilot
	mentionsCopilot := h.mentionsCopilot(ctx, event, review)
	if len(mentionsCopilot) == 0 {
		logger.Info("Ignoring review because it does not mention Copilot")
		return nil
	}

	logger.Info("Waking up Copilot because new feedback is actionable")

	// ✅ All validation/permission checks passed, now we start doing things

	// Add a 👀 reaction to acknowledge the review
	jobutils.AddReactionsForReview(ctx, h.obsv, gh, review)

	allJobs, pendingJob, err := jobutils.JobsForAssignment(ctx, h.obsv, h.jobService, gh, h.ffClient, assignment)
	if err != nil {
		return fmt.Errorf("failed to get jobs for assignment: %w", err)
	}

	actor, err := h.getJobActor(ctx, event.Actor)
	if err != nil {
		return fmt.Errorf("failed to get job actor: %w", err)
	}

	var builder *jobservice.JobBuilderWithAssignmentAndActor

	if pendingJob == nil {
		builder = h.jobService.
			NewJobBuilder(jobs.AgentActionFixPRComment, pr.HeadRef.Name).
			ForAssignment(assignment).
			WithJobActor(*actor).
			WithLabelsFrom(pr)
	} else {
		builder = h.jobService.
			JobBuilderForJob(assignment, pendingJob).
			WithJobActor(*actor)
	}

	builder = builder.
		WithJobInitHook(func(j *jobs.Job) {
			j.BranchName = pr.HeadRef.Name
			// Make sure this review is added to the pending job so the LLM considers it
			j.ReviewIDs = append(j.ReviewIDs, review.GetID())
			// Add all other (qualifying) comments and reviews that haven't been included on a job yet.
			jobutils.AddUnprocessedCommentsAndReviewsToJob(gh, actx, allJobs, j)
		}).
		WithEvent(jobservice.Event{
			Type:        jobs.EventTypePullRequestReview,
			URL:         event.EventUrl,
			Identifiers: []string{fmt.Sprintf("%d", review.GetID())},
		}).
		WithProblemStatementBuilder(func(c context.Context, j *jobs.Job) (jobs.ProblemStatement, error) {
			return problemstatement.NewPullRequestBuilder(h.obsv, gh, actx, j, githubtwirp.NewAuthorResolver(h.obsv, h.ghTwirp, h.ffClient), h.ffClient).Build(c)
		})

	if has, runningJobID := jobs.HasQueuedOrRunningJobs(allJobs); has {
		h.obsv.LoggerWithTelemetry(ctx).Info("Job pending but not launching agent because there is another job in progress",
			kvp.String("running_job_id", runningJobID))

		_, _, err = builder.Build(ctx, gh)
		if err != nil {
			return fmt.Errorf("failed to build job: %w", err)
		}
		return nil
	}

	_, pendingJob, err = builder.WithNewSession().Build(ctx, gh)
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

func (h *Handler) mentionsCopilot(ctx context.Context, event PullRequestReviewSubmitEvent, review *github.GQLPullRequestReview) []github.ReviewOrReviewComment {
	if h.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgenticAppsProvider, &event) {
		return reviewsWithCopilotMention(review, h.appProvider.IsAgenticMention)
	}

	return reviewsWithCopilotMention(review, github.DoesMentionCopilot)
}

func reviewsWithCopilotMention(review *github.GQLPullRequestReview, mentionChecker func(string) bool) []github.ReviewOrReviewComment {
	var reviews []github.ReviewOrReviewComment

	// If the main body mentions Copilot, we can return early
	if mentionChecker(review.GetBody()) {
		return []github.ReviewOrReviewComment{review}
	}

	for _, comment := range review.Comments.Nodes {
		if mentionChecker(comment.GetBody()) {
			reviews = append(reviews, &comment)
		}
	}

	return reviews
}

func (h *Handler) handleReviewOnNonCopilotAuthoredPullRequest(ctx context.Context, gh github.ClientInterface, actx *github.PullRequestContext, event PullRequestReviewSubmitEvent) error {
	ctx, span := h.obsv.Tracer.Start(ctx, "events.Handler.handleReviewOnNonCopilotAuthoredPullRequest")
	defer span.End()

	pr := actx.PullRequest
	repo := actx.Repository
	owner := repo.Owner

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

	_, job, err := h.jobService.
		NewJobBuilder(jobs.AgentActionFixPRComment, pr.HeadRef.Name).
		WithNewAssignment(owner.GetID(), repo.ID, owner.NodeID, repo.NodeID, owner.Login, repo.Name, pullRequestResource(pr.GetID())).
		WithJobActor(*actor).
		WithProblemStatementBuilder(func(c context.Context, j *jobs.Job) (jobs.ProblemStatement, error) {
			// Create problem statement for the stack PR
			// Importantly, the problem statement will focus specifically on the review comments that need
			// to be addressed by Copilot, not the entire PR.
			return problemstatement.NewReviewBuilder(h.obsv, gh, actx, j, review.GetID(), githubtwirp.NewAuthorResolver(h.obsv, h.ghTwirp, h.ffClient)).Build(c)
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
			body := h.generateReviewStackBodyBase(ctx, event, review)

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
		WithNewSession().
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
	if _, err := gh.CreateComment(ctx, int64(repo.ID), pr.Number, commentBody); err != nil {
		// Log the error but don't fail the entire operation
		h.obsv.LogAndReportError(ctx, err, "failed to comment on original PR")
	}

	return nil
}

func (h *Handler) generateReviewStackBodyBase(ctx context.Context, event PullRequestReviewSubmitEvent, review *github.GQLPullRequestReview) string {
	reviewsWithCopilotMentions := h.mentionsCopilot(ctx, event, review)

	// If only the top-level review mentioned Copilot, we can link to that review directly
	// At this point we've already confirmed that at least one review/comment mentioned Copilot
	var body string
	if len(reviewsWithCopilotMentions) == 1 {
		r := reviewsWithCopilotMentions[0]
		body = fmt.Sprintf("Triggering review: %s\n> %s", r.GetUrl(), strings.ReplaceAll(r.GetBody(), "\n", "\n> "))
	} else {
		body = "Triggering reviews:"
		for _, r := range reviewsWithCopilotMentions {
			body += fmt.Sprintf("\n- %s\n> %s", r.GetUrl(), strings.ReplaceAll(r.GetBody(), "\n", "\n> "))
		}
	}

	return body
}
