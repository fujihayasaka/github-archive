package events

import (
	"context"
	"fmt"
	"slices"
	"strings"
	"time"

	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/joberrors"
	"github.com/github/sweagentd/internal/jobs"
	js "github.com/github/sweagentd/internal/jobservice"
	"github.com/github/sweagentd/internal/jobutils"
	"github.com/github/sweagentd/internal/limiter"
	"github.com/github/sweagentd/internal/problemstatement"
	"github.com/github/sweagentd/internal/requestctx"
)

const timeCheckBufferSeconds = 1

func (h *Handler) OnIssueAssigned(ctx context.Context, event IssueAssignmentEvent) error {
	// for this event, the actor is the user that set/cleared the assignee in the issue.
	assigner := event.Actor

	// Determine if this event assigned Copilot.
	// Use new singular Assignee field if feature flag enabled, otherwise use legacy Assignees slice.
	var assignedToCopilot bool
	if event.Assignee != "" {
		assignedToCopilot = h.ghFactory.UserIsCopilot(event.Assignee)
	} else {
		h.obsv.LoggerWithTelemetry(ctx).Warn("empty Assignee field; falling back to Assignees slice")
		assignedToCopilot = h.ghFactory.ContainsCopilotUser(event.Assignees)
	}

	// Ignore events for closed issues or issues not assigned to Copilot
	if !event.Issue.IsOpen || !assignedToCopilot {
		return nil
	}

	gh, err := h.ghFactory.NewClientForRepo(ctx, &event)
	if err != nil {
		return fmt.Errorf("failed to create GitHub client: %w", err)
	}

	// Only process events where the actor has write access to the repo
	permission, err := gh.GetUserPermissionsForRepositoryByID(ctx, event.Repo.ID, assigner.Login)
	if err != nil {
		return fmt.Errorf("getting user permissions for repository: %w", err)
	}
	if !permission.Push {
		h.obsv.LoggerWithTelemetry(ctx).Info("Ignoring assignment because actor does not have write access to the repo")
		return nil
	}

	// The issue assigned event includes an array of assignees, so we don't know
	// if this specific event represents the bot being assigned or not.
	assignment, err := h.getAssignmentForIssue(ctx, event.Repo.OwnerID, event.Repo.ID, event.Issue.ID)
	if err != nil {
		return fmt.Errorf("getting assignment: %w", err)
	}

	if assignment != nil {
		// We have an existing active assignment, so we can assume that this
		// event does not represent the bot being assigned to the issue.
		return nil
	}

	actx, err := gh.GetIssueContext(ctx, event.Repo.NodeID, event.Issue.Number)
	if err != nil {
		return fmt.Errorf("failed to get issue context: %w", err)
	}

	// If the issue has been edited since the event was triggered, we need to use an older version of the issue body to ensure
	// nobody altered the issue between the event trigger and processing. See https://github.com/github/sweagentd/issues/2473
	if h.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentIssueBodyEditCheck, &event) {
		h.obsv.LoggerWithTelemetry(ctx).Info("Feature flag to check issue assignment timestamp enabled")
		success := h.adjustIssueBodyIfRequired(ctx, gh, actx, event)
		if !success {
			return nil
		}
	} else {
		h.obsv.LoggerWithTelemetry(ctx).Info("Feature flag to check issue assignment timestamp NOT enabled")
	}

	repo := actx.Repository
	owner := repo.Owner
	issue := actx.Issue

	// Check if the repository has been initialized (has any actual contents)
	// before we create an assignment.
	// TODO: Support uninitialized repos, and let the agent do the initialization.
	if repo.DefaultBranchRef == nil {
		tags, _, _ := requestctx.ToTelemetry(ctx, nil)
		h.obsv.Statter.Counter("events.Handler.onIssueAssigned.failed.uninitializedRepo", tags, 1)

		if err := h.addErrorComment(ctx, gh, actx, joberrors.ErrorRepositoryUninitialized); err != nil {
			return err
		}
		return nil
	}

	// We don't have an existing active assignment, so we can assume that this
	// event does represent the bot being assigned to the issue.
	assignment = jobs.NewAssignment(owner.GetID(), repo.ID, owner.NodeID, repo.NodeID, owner.Login, repo.Name, issueResource(issue.GetID()))

	assignment, err = h.jobsStore.CreateAssignment(ctx, assignment)
	if err != nil {
		return err
	}

	err = h.onIssueAssignedBuilder(ctx, gh, assignment, actx, event)
	if err != nil {
		if limiter.IsAnyLimiterError(err) {
			return err
		}
		// TODO: (colbylwilliams) determine if we still need this
		return jobutils.NewUnhandledErrorWithIssueComment(ctx, err, assignment, true, event.Actor.Login, event.Issue.Number)
	}
	return nil
}

// Function to handle race condition. If the issue has been edited since the event was triggered, we need to use an older version of the
// issue body to ensure nobody altered the issue between the event trigger and processing. See https://github.com/github/sweagentd/issues/2473
//
// The function returns true if any required adjustments were successfully made or not adjustments were needed.
func (h *Handler) adjustIssueBodyIfRequired(ctx context.Context, gh github.ClientInterface, actx *github.IssueContext, event IssueAssignmentEvent) bool {
	// We are dealing with UTC time values here, so we nee to factor in that the update could have happened in the same second
	adjustedTS := event.Timestamp.Add(-timeCheckBufferSeconds * time.Second)
	// See if there are any edits to the issue body, and if so, see if we can find a previous edit within 1s of
	// the event time window. Note that LastEditedAt can be nil, but CreatedAt and UpdatedAt will always have a value.
	if actx.Issue.LastEditedAt == nil || actx.Issue.CreatedAt.Equal(*actx.Issue.LastEditedAt) || actx.Issue.LastEditedAt.Before(adjustedTS) {
		return true
	}

	h.obsv.LoggerWithTelemetry(ctx).Info("Issue may have been updated since assignment, verifying correct body")
	// Get most recent 20 content edits for the issue body to see if we can find one before the timestamp
	edits, err := gh.GetIssueUserContentEdits(ctx, actx.Issue.NodeID)
	if err != nil {
		h.obsv.LogAndReportError(ctx, err, "failed to get user content edits for issue")
		return false
	}

	// We should never be here in a scenario where there are no edits, but double check for future changes
	if len(edits) == 0 {
		// Should never happen, since actx.Issue.LastEditedAt should be nil, but cover bases for replication lag
		h.obsv.LoggerWithTelemetry(ctx).Info("No edits found for issue, using current Body")
		return true
	}

	// Sort by EditedAt descending in case default sort order from API changes.
	// NOTE: UpdatedAt may != EditedAt since when the first edit happens, two records are added
	// with the same update time, but different edit times (one being for the original body)
	slices.SortFunc(edits, func(a, b github.UserContentEdit) int {
		return b.EditedAt.Compare(a.EditedAt)
	})
	diff := ""
	for _, edit := range edits {
		if edit.EditedAt.Before(adjustedTS) {
			// Use the body from the last edit before the event timestamp
			h.obsv.LoggerWithTelemetry(ctx).Info("Found diff for earlier timestamp")
			diff = edit.Diff
			break
		}
	}
	if diff == "" {
		// If we have seen 20 edits within the same second, this is likely an attempt to exploit a race condition, so ignore
		h.obsv.LogAndReportError(ctx, err, "failed to find older edit for issue")
		return false
	}

	// Otherwise, use the found diff as the issue body
	actx.Issue.Body = diff
	return true
}

func (h *Handler) onIssueAssignedBuilder(ctx context.Context, gh github.ClientInterface, assignment *jobs.Assignment, actx *github.IssueContext, event IssueAssignmentEvent) error {
	ctx, span := h.obsv.Tracer.Start(ctx, "events.Handler.onIssueAssigned")
	defer span.End()

	repo := actx.Repository
	issue := actx.Issue

	jobActor, err := h.getJobActor(ctx, event.Actor)
	if err != nil {
		return fmt.Errorf("failed to get job actor: %w", err)
	}

	_, job, err := h.jobService.NewJobBuilder(jobs.AgentActionFix, repo.GetDefaultBranch()).
		ForAssignment(assignment).
		WithJobActor(*jobActor).
		WithJobInitHook(func(j *jobs.Job) {
			j.IssueNumber = issue.Number
		}).
		WithEvent(js.Event{
			Type:        jobs.EventTypeIssueAssignment,
			URL:         event.EventUrl,
			Identifiers: []string{fmt.Sprintf("%d", issue.GetID())},
		}).
		WithLabelsFrom(issue).
		WithProblemStatementBuilder(func(c context.Context, job *jobs.Job) (jobs.ProblemStatement, error) {
			return problemstatement.NewIssueBuilder(h.obsv, gh, actx, githubtwirp.NewAuthorResolver(h.obsv, h.ghTwirp, h.ffClient)).Build(c)
		}).
		WithFeatures(jobs.EnvironmentFeatures{
			Branch: &jobs.BranchFeature{
				BaseRef: repo.DefaultBranchRef.Name,
				Name:    fmt.Sprintf("fix-%d", issue.Number),
			},
			PullRequest: &jobs.PullRequestFeature{
				TitlePlaceholder: fmt.Sprintf("[WIP] %s", issue.Title),
				BodyPlaceholder:  getPRBodyBase(issue.Body, issue.Number),
			},
		}).
		WithBranchRuleViolationHook(h.handleRulesViolation(actx)).
		WithExperiments().
		WithOnboarding().
		Build(ctx, gh)

	if err != nil {
		return fmt.Errorf("failed to build job: %w", err)
	}

	h.obsv.LoggerWithTelemetry(ctx).Info("Queuing new job for assigned issue")

	_, err = h.jobService.QueueJobForExecution(ctx, job)
	if err != nil {
		return fmt.Errorf("failed to queue job: %w", err)
	}

	return nil
}

func getPRBodyBase(issueBody string, issueNumber int) string {
	return fmt.Sprintf("Thanks for assigning this issue to me. I'm starting to work on it and will keep this PR's description up to date as I form a plan and make progress.\n\nOriginal issue description:\n\n> %s\n\n\nFixes #%d.", strings.ReplaceAll(issueBody, "\n", "\n> "), issueNumber)
}

func (h *Handler) getAssignmentForIssue(ctx context.Context, ownerID, repoID, issueID int64) (*jobs.Assignment, error) {
	resource := issueResource(issueID)

	assignment, err := h.jobsStore.GetAssignmentForResource(ctx, ownerID, repoID, resource)
	if err != nil {
		return nil, fmt.Errorf("failed to get assignment: %w", err)
	}

	return assignment, nil
}

func (h *Handler) handleRulesViolation(actx *github.IssueContext) js.BranchRuleViolationHookFunc {
	return func(ctx context.Context, gh github.ClientInterface, actorLogin string, assignment *jobs.Assignment, result *js.CheckRulesResult) error {
		if err := h.jobsStore.DetachAssignmentResources(ctx, assignment); err != nil {
			return fmt.Errorf("failed to detach assignment after checking rules: %w", err)
		}
		errWith := jobutils.NewUnhandledRulesErrorWithIssueComment(ctx, nil, assignment, actorLogin, actx.Issue.Number, result)
		body, err := errWith.GenerateComment()
		if err != nil {
			return fmt.Errorf("failed to generate comment body: %w", err)
		}

		tags, _, _ := requestctx.ToTelemetry(ctx, nil)
		h.obsv.Statter.Counter("events.Handler.onIssueAssigned.failed.rulesViolation", tags, 1)

		if err := h.addErrorComment(ctx, gh, actx, body); err != nil {
			return fmt.Errorf("failed to create comment for rules violation: %w", err)
		}

		return nil
	}
}

// addErrorComment adds a comment to the issue with the given body.
// If there are existing error comments by Copilot, it minimizes them as 'outdated'
// before adding the new comment.
// This is to ensure that the user is not overwhelmed with multiple error comments
// from Copilot on the same issue, and only sees the most recent one.
func (h *Handler) addErrorComment(ctx context.Context, gh github.ClientInterface, actx *github.IssueContext, body string) error {
	if err := actx.Issue.RemoveReaction(ctx, gh, github.GQLReactionContentEyes); err != nil {
		h.obsv.LogAndReportError(ctx, err, "failed to remove reaction")
	}
	return joberrors.CreateErrorCommentOnIssue(ctx, h.obsv, gh, actx, body)
}
