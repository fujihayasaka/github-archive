package events

import (
	"context"
	"fmt"
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
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/sweagentd"
)

type mentionable interface {
	HasCopilotMention() bool
}

func (h *Handler) openStackedPR(ctx context.Context, actor sweagentd.RepositoryWithActor, m mentionable, commentMentionsAgenticActor bool) bool {
	stackPRsEnabled := h.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CodingAgentStackPRs, actor)
	if !stackPRsEnabled {
		return false
	}

	if h.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgenticAppsProvider, actor) {
		return commentMentionsAgenticActor
	}

	return m.HasCopilotMention()
}

type actorWithCopilotCheck interface {
	sweagentd.ActorWithLogin

	IsCopilot(github.CopilotUserChecker) bool
}

func (h *Handler) isCopilotActor(ctx context.Context, checker github.CopilotUserChecker, actor actorWithCopilotCheck) bool {
	if h.ffClient.IsEnabledForUser(ctx, featureflags.CopilotSWEAgenticAppsProvider, actor.GetActorID()) {
		return h.appProvider.IsAgenticActor(actor)
	}

	return actor.IsCopilot(checker)
}

func (h *Handler) OnPullRequestCommentCreated(ctx context.Context, event PullRequestCommentCreatedEvent) error {
	assignment, err := h.assignmentForPR(ctx, event.Repo.OwnerID, event.Repo.ID, nil, &event.PullRequest.Number)
	if err != nil {
		return fmt.Errorf("failed to get assignment for pull request: %w", err)
	}

	var commentMentionsAgenticActor bool
	if h.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgenticAppsProvider, &event) {
		commentMentionsAgenticActor = h.appProvider.IsAgenticMention(event.Comment.Body)
	}

	openStackedPR := h.openStackedPR(ctx, &event, event.Comment, commentMentionsAgenticActor)

	if assignment == nil && !openStackedPR {
		h.obsv.LoggerWithTelemetry(ctx).Info("No assignment found for pull request, skipping comment processing")
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
		h.obsv.LoggerWithTelemetry(ctx).Info("Ignoring comment because it is on a cross-repository pull request")
		return nil
	}

	h.setCtxPullRequestID(ctx, actx.PullRequest.GetID(), actx.PullRequest.Number)

	// The user commented on a non-Copilot PR, @-mentioning Copilot.
	if openStackedPR && !h.isCopilotActor(ctx, gh, actx.PullRequest.Author) {
		h.obsv.Increment(ctx, "events.handle_comment_on_non_copilot_authored_pr", nil)
		return h.handleCommentOnNonCopilotAuthoredPullRequest(ctx, gh, actx, event)
	}

	err = h.onPullRequestCommentCreated(ctx, gh, assignment, actx, event, commentMentionsAgenticActor)
	if err != nil {
		if limiter.IsAnyLimiterError(err) {
			return err
		}

		// TODO: (colbylwilliams) determine if we still need this
		return jobutils.NewUnhandledErrorWithPRComment(ctx, err, assignment, false, event.Actor.Login)
	}

	return nil
}

func (h *Handler) onPullRequestCommentCreated(
	ctx context.Context, gh github.ClientInterface, assignment *jobs.Assignment, actx *github.PullRequestContext, event PullRequestCommentCreatedEvent, agenticMention bool,
) error {
	ctx, span := h.obsv.Tracer.Start(ctx, "events.Handler.onPullRequestCommentCreated")
	defer span.End()

	pr := actx.PullRequest

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

	// Ignore events for closed PRs or PRs not authored by Copilot
	if pr.IsClosed() || !h.isCopilotActor(ctx, gh, pr.Author) {
		logger.Info("Ignoring comment because pull request is closed or not authored by Copilot")
		return nil
	}

	// Ignore comments authored by Copilot or other bots
	if h.isCopilotActor(ctx, gh, comment.Author) || comment.Author.IsBot() {
		logger.Info("Ignoring comment because it was authored by Copilot or a bot")
		return nil
	}

	// Only process events where the actor has write access to the repo
	if !actx.PermissionsFor(comment.Author).Push {
		logger.Info("Ignoring comment because actor does not have write access to the repo")
		return nil
	}

	// Only wake if the comment mentions Copilot
	commentMentionsCopilot := event.Comment.MentionsCopilot
	if h.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgenticAppsProvider, &event) {
		commentMentionsCopilot = agenticMention
	}

	if !commentMentionsCopilot {
		logger.Info("Ignoring review because it does not mention Copilot")
		return nil
	}

	logger.Info("Waking up Copilot because new feedback is actionable")

	// ✅ All validation/permission checks passed, now we start doing things

	// Add a 👀 reaction to acknowledge the (actionable) comment
	if err := comment.AddReaction(ctx, gh, github.GQLReactionContentEyes); err != nil {
		// Bummer, but we don't want to fail the job
		h.obsv.LogAndReportError(ctx, err, "failed to add reaction")
	}

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
			// Make sure this comment is added to the pending job so the LLM considers it
			j.CommentIDs = append(j.CommentIDs, comment.GetID())
			// Add all other (qualifying) comments and reviews that haven't been included on a job yet.
			jobutils.AddUnprocessedCommentsAndReviewsToJob(gh, actx, allJobs, j)
		}).
		WithEvent(jobservice.Event{
			Type:        jobs.EventTypePullRequestComment,
			URL:         event.EventUrl,
			Identifiers: []string{fmt.Sprintf("%d", comment.GetID())},
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

func (h *Handler) handleCommentOnNonCopilotAuthoredPullRequest(ctx context.Context, gh github.ClientInterface, actx *github.PullRequestContext, event PullRequestCommentCreatedEvent) error {
	ctx, span := h.obsv.Tracer.Start(ctx, "events.Handler.handleCommentOnNonCopilotAuthoredPullRequest")
	defer span.End()

	pr := actx.PullRequest
	repo := actx.Repository
	owner := repo.Owner

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

	_, job, err := h.jobService.
		NewJobBuilder(jobs.AgentActionFixPRComment, pr.HeadRef.Name).
		WithNewAssignment(owner.GetID(), repo.ID, owner.NodeID, repo.NodeID, owner.Login, repo.Name, pullRequestResource(pr.GetID())).
		WithJobActor(*jobActor).
		WithProblemStatementBuilder(func(c context.Context, j *jobs.Job) (jobs.ProblemStatement, error) {
			// Create problem statement for the stack PR
			// Importantly, the `actx` is still for the original PR, which is what we want
			// since we want the problem statement to reflect the full context of the original PR
			// and the comment that triggered the stack PR creation.
			return problemstatement.NewPullRequestBuilder(h.obsv, gh, actx, j, githubtwirp.NewAuthorResolver(h.obsv, h.ghTwirp, h.ffClient), h.ffClient).Build(c)
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

			body := fmt.Sprintf("Triggering comment (%s):\n> %s\n", comment.GetUrl(), strings.ReplaceAll(comment.GetBody(), "\n", "\n> "))
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
		userDetails, err := githubtwirp.GetCopilotUserDetails(ctx, h.ghTwirp, actor.ID)
		if err != nil {
			h.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to get copilot user for tracking ID")
		} else {
			jobActor.TrackingID = userDetails.AnalyticsTrackingId
		}
	}

	return jobActor, nil
}
