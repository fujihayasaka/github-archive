package jobapi

import (
	"context"
	"fmt"
	"strings"

	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobservice"
	"github.com/github/sweagentd/internal/jobutils"
	ps "github.com/github/sweagentd/internal/problemstatement"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/sweagentd"
	gg "github.com/google/go-github/v75/github"
)

func (h *Handler) createJob(
	ctx context.Context,
	gh github.ClientInterface,
	req *NewJobAPIRequest,
	user *requestctx.UserInfo,
	agent sweagentd.CustomAgent,
	repo *gg.Repository,
	async bool, // if true, create job asynchronously (without branch/PR/experiments)
) (*jobs.Assignment, *jobs.Job, error) {
	logger := h.obsv.LoggerWithTelemetry(ctx)
	logger.Info("Using job builder to create assignment and job")

	pullRequestFeature := PullRequestFeature{}
	if req.Features.PullRequest != nil {
		pullRequestFeature = *req.Features.PullRequest
	}

	baseRef := fmt.Sprintf("refs/heads/%s", repo.GetDefaultBranch())
	if pullRequestFeature.BaseRef != "" {
		baseRef = pullRequestFeature.BaseRef
	}

	// If the user did not provide an event type, default to a generic api call
	// received event type
	eventType := req.EventType
	if eventType == "" {
		eventType = jobs.EventTypeApiCallReceived
	}

	problemStatement := jobs.ProblemStatement{
		Content:           req.ProblemStatement,
		ContentFilterMode: req.ContentFilterMode,
	}

	// Truncate the problem statement content if it exceeds the max length allowed.
	// This should be handled by validation, but just in case we call truncate here
	// to ensure the request doesn't fail later in the process.
	problemStatement.Content = truncate(problemStatement.Content, ps.MaxProblemStatementLength)

	// Ensure the commit count is at least 1
	// TODO: Get the actual commit count for the branch on the job
	problemStatement.CommitCount = max(1, problemStatement.CommitCount)

	// If no content filter mode is provided, we default to hidden characters
	if problemStatement.ContentFilterMode == "" {
		problemStatement.ContentFilterMode = jobs.ProblemStatementContentFilterModeHiddenCharacters
	}

	jobRunOpts := jobs.RunOptions{}

	// Make sure run name has a value and it doesn't exceed the max length
	jobRunOpts.RunName = req.RunName
	if jobRunOpts.RunName == "" {
		jobRunOpts.RunName = "Running Copilot"
	}
	jobRunOpts.RunName = capLength(jobRunOpts.RunName, github.MaxRunNameLength)

	// TitlePlaceholder is used as the title of the PR until the AI updates it.
	// It must have a valid value in order to create the PR, so we set a default
	// if one is not provided.
	if pullRequestFeature.Title == "" {
		pullRequestFeature.Title = "Copilot Request"
	}

	// Length constraint should be handled by validation, but just in case
	pullRequestFeature.Title = truncate(pullRequestFeature.Title, github.MaxPullRequestTitleLength)

	// Prefix the title with "[WIP]" to indicate it's a work in progress, but
	// only if it doesn't make the title exceed the max length
	titleWithPrefix := fmt.Sprintf("[WIP] %s", pullRequestFeature.Title)
	if len(titleWithPrefix) < github.MaxPullRequestTitleLength {
		pullRequestFeature.Title = titleWithPrefix
	}

	// BodyPlaceholder is used as the body (description) of the PR until
	// the AI updates it. It must have a valid value in order to create the PR.
	//
	// TODO: We should move response suffix to the assignment since it can be used
	// across jobs. Right now there is logic to look for a specific separator in
	// internal/agentcallback/jobmanager that was added as a part of logic to
	// update the PR in fix-pr-comment.
	if pullRequestFeature.BodyPlaceholder == "" {
		pullRequestFeature.BodyPlaceholder = PRBodyPrefix
	}

	// Length constraint should be handled by validation, but just in case
	pullRequestFeature.BodyPlaceholder = truncate(pullRequestFeature.BodyPlaceholder, MaxPullRequestBodyPlaceholderLength)

	// ResponseBodySuffix is appended to the body (description) of the PR body
	// both initially and when the body is updated by the AI. It includes any
	// the user provided suffix, the (possibly truncated) original problem
	// statement (unless the event type is Slack), and a random tip for the user if there is room.
	//
	// At this point, the suffix only includes the user provided suffix. The
	// length constraint should be handled by validation, but truncate just in case
	pullRequestFeature.BodySuffix = truncate(pullRequestFeature.BodySuffix, MaxPullRequestBodySuffixLength)

	problemStatementQuote := ""
	// Only include the original prompt in the PR body if the event type is not Slack or Slack Staging
	if eventType != jobs.EventTypeSlack && eventType != jobs.EventTypeSlackStaging {
		problemStatementQuote = problemStatement.Content
		// We want to format the problem statement we include in the PR body as a
		// markdown quote, but also need to make sure the resulting value doesn't
		// exceed the maximum length designated for the problem statement after adding
		// the markdown quote characters (>).
		// If the initial problem statement is less than the maximum allowed length,
		// we attempt to quote it. If the result exceeds the max, we fall back to
		// truncating the original problem statement to fit within the max length.
		if len(problemStatementQuote) < MaxPullRequestBodyProblemStatementQuoteLength {
			// try to quote the problem statement and see if it fits within the max length
			withMarkdown := fmt.Sprintf("> %s\n", strings.ReplaceAll(problemStatementQuote, "\n", "\n> "))
			if len(withMarkdown) < MaxPullRequestBodyProblemStatementQuoteLength {
				// if the markdown version is within the max length, use it
				problemStatementQuote = withMarkdown
			}
		}

		// Again, length constraint should be handled by validation, but call truncate
		// just in case, then wrap it in the HTML details/summary tags to make it
		// collapsible in the PR body
		problemStatementQuote = truncate(problemStatementQuote, MaxPullRequestBodyProblemStatementQuoteLength)
		problemStatementQuote = fmt.Sprintf(PullRequestBodyProblemStatementQuoteWrapper, problemStatementQuote)
	}

	// We also want to include the subagent name in the PR body suffix
	customAgentQuote := generateCustomAgentQuote(agent)

	// Now add the suffix separator and problem statement quote to the to the
	// beginning of the response body suffix to ensure it is always at the end
	// of the PR body.
	pullRequestFeature.BodySuffix = constructResponseBodySuffix(problemStatementQuote, customAgentQuote, pullRequestFeature.BodySuffix)

	features := jobs.EnvironmentFeatures{
		PullRequest: &jobs.PullRequestFeature{
			TitlePlaceholder: pullRequestFeature.Title,
			BodyPlaceholder:  pullRequestFeature.BodyPlaceholder,
			BodySuffix:       pullRequestFeature.BodySuffix,
			Labels:           pullRequestFeature.Labels,
			BaseRef:          pullRequestFeature.BaseRef,
			HeadRef:          pullRequestFeature.HeadRef,
		},
	}

	// TODO: Let's see if we can move this into the builder or another shared
	// place to resolve display logins for all surfaces
	jobActor := jobs.JobActor{
		ID:         int64(user.ID),
		Login:      user.Login,
		TrackingID: user.TrackingID,
	}

	builder := h.jobService.NewJobBuilder(jobs.AgentActionFix, baseRef).
		WithNewAssignmentWithCustomAgent(*repo.Owner.ID, *repo.ID, *repo.Owner.NodeID, *repo.NodeID, *repo.Owner.Login, *repo.Name, agent).
		WithJobActor(jobActor).
		WithRunOptions(jobRunOpts).
		WithFeatures(features).
		WithProblemStatement(&problemStatement).
		WithEvent(jobservice.Event{
			Type:        eventType,
			URL:         req.EventURL,
			Identifiers: req.EventIdentifiers,
			Content:     req.EventContent,
		}).
		WithNewSession()

	if async {
		builder = builder.WithoutCreatingFeatures()
	}

	if !async {
		builder = builder.WithExperiments()
	}

	assignment, job, err := builder.Build(ctx, gh)

	return assignment, job, err
}

func generateCustomAgentQuote(agent sweagentd.CustomAgent) string {
	// We also want to include the subagent name in the PR body suffix
	customAgentQuote := ""
	// But only if it's not the default Copilot agent
	if !agent.IsCopilot() {
		agentName := agent.DisplayName()
		agentName = truncate(agentName, MaxPullRequestBodyAgentNameLength)
		customAgentQuote = fmt.Sprintf(PullRequestBodyAgentNameWrapper, agentName)

		agentDescription := agent.Description()
		if agentDescription != "" {
			agentDescription = fmt.Sprintf("> %s", strings.ReplaceAll(agentDescription, "\n", "\n> "))
			customAgentQuote += truncateAgentDescriptionWithLink(agentDescription, agent.RepoOwner(), agent.RepoName(), agent.Name(), MaxPullRequestBodyAgentDescriptionLength)
			customAgentQuote += "\n"
		}
	}
	if customAgentQuote != "" {
		customAgentQuote += "\n"
	}
	return customAgentQuote
}

// constructResponseBodySuffix constructs the final ResponseBodySuffix by combining
// the problem statement quote, custom agent quote, and user-provided suffix with proper spacing.
func constructResponseBodySuffix(problemStatementQuote, customAgentQuote, userProvidedSuffix string) string {
	return jobutils.PullRequestBodySuffixSeparator + problemStatementQuote + customAgentQuote + userProvidedSuffix
}
