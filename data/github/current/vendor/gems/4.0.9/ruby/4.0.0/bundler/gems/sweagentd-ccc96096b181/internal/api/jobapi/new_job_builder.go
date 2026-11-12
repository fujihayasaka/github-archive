package jobapi

import (
	"context"
	"fmt"
	"strings"
	"unicode/utf8"

	"github.com/github/sweagentd/internal/customagent"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobservice"
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

	var pullRequestFeature *PullRequestFeature
	if req.Features != nil && req.Features.PullRequest != nil {
		pullRequestFeature = req.Features.PullRequest
	}

	baseRef := determineBaseRef(req, repo)

	// If the user did not provide an event type, default to a generic api call
	// received event type
	eventType := req.EventType
	if eventType == "" {
		eventType = jobs.EventTypeAPICallReceived
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

	agenticApp, err := h.appProvider.FindByID(int64(req.AgentID))
	if err != nil {
		return nil, nil, goerrors.Errorf("failed to find agentic app by ID: %w", err)
	}

	// Make sure run name has a value and it doesn't exceed the max length
	jobRunOpts.RunName = req.RunName
	if jobRunOpts.RunName == "" {
		jobRunOpts.RunName = fmt.Sprintf("Running %s", agenticApp.AppName())
	}
	jobRunOpts.RunName = capLength(jobRunOpts.RunName, github.MaxRunNameLength)

	// TitlePlaceholder is used as the title of the PR until the AI updates it.
	// It must have a valid value in order to create the PR, so we set a default
	// if one is not provided.
	if pullRequestFeature != nil {
		if pullRequestFeature.Title == "" {
			pullRequestFeature.Title = fmt.Sprintf("%s request", agenticApp.AppName())
		}

		// Length constraint should be handled by validation, but just in case
		pullRequestFeature.Title = truncate(pullRequestFeature.Title, github.MaxPullRequestTitleLength)

		// Prefix the title with "[WIP]" to indicate it's a work in progress, but
		// only if it doesn't make the title exceed the max length
		titleWithPrefix := fmt.Sprintf("[WIP] %s", pullRequestFeature.Title)
		if utf8.RuneCountInString(titleWithPrefix) < github.MaxPullRequestTitleLength {
			pullRequestFeature.Title = titleWithPrefix
		}
	}

	// BodyPlaceholder is used as the body (description) of the PR until
	// the AI updates it. It must have a valid value in order to create the PR.
	//
	// TODO: We should move response suffix to the assignment since it can be used
	// across jobs. Right now there is logic to look for a specific separator in
	// internal/agentcallback/jobmanager that was added as a part of logic to
	// update the PR in fix-pr-comment.
	if pullRequestFeature != nil {
		if pullRequestFeature.BodyPlaceholder == "" {
			pullRequestFeature.BodyPlaceholder = jobservice.PRBodyPrefix
		}

		// Length constraint should be handled by validation, but just in case
		pullRequestFeature.BodyPlaceholder = truncate(pullRequestFeature.BodyPlaceholder, jobservice.MaxPullRequestBodyPlaceholderLength)

		// ResponseBodySuffix is appended to the body (description) of the PR body
		// both initially and when the body is updated by the AI. It includes any
		// the user provided suffix, the (possibly truncated) original problem
		// statement (unless the event type is Slack), and a random tip for the user if there is room.
		//
		// At this point, the suffix only includes the user provided suffix. The
		// length constraint should be handled by validation, but truncate just in case
		pullRequestFeature.BodySuffix = truncate(pullRequestFeature.BodySuffix, jobservice.MaxPullRequestBodySuffixLength)
	}

	problemStatementQuote := ""
	// Only include the original prompt in the PR body if the event type is not Slack
	if eventType != jobs.EventTypeSlack {
		problemStatementQuote = GenerateProblemStatementQuote(problemStatement.Content)
	}

	// We also want to include the subagent name in the PR body suffix
	customAgentQuote := GenerateCustomAgentQuote(agent)

	if pullRequestFeature != nil {
		// Separate original prompt and user suffix into distinct sections
		originalPromptSection := constructOriginalPromptSection(problemStatementQuote, customAgentQuote)
		userSuffixSection := constructUserSuffixSection(pullRequestFeature.BodySuffix)
		pullRequestFeature.BodySuffix = originalPromptSection + userSuffixSection
	}

	features := BuildEnvironmentFeatures(req.Features, pullRequestFeature)

	// TODO: Let's see if we can move this into the builder or another shared
	// place to resolve display logins for all surfaces
	jobActor := jobs.JobActor{
		ID:         int64(user.ID),
		Login:      user.Login,
		TrackingID: user.TrackingID,
	}

	action := jobs.AgentActionFix
	if features.PullRequest == nil && h.ffClient.IsEnabledForUser(ctx, featureflags.CodingAgentProposeTasks, int64(user.ID)) {
		action = jobs.AgentActionTask
	}

	useAsyncSessions := h.ffClient.IsEnabledForUserOrRepo(ctx, featureflags.CopilotSWEAgentUseAsyncSessions, int64(user.ID), *repo.ID)

	builder := h.jobService.NewJobBuilder(action, repo, baseRef).
		WithNewAssignmentWithCustomAgent(*repo.Owner.ID, *repo.ID, *repo.Owner.NodeID, *repo.NodeID, *repo.Owner.Login, *repo.Name, useAsyncSessions, agent).
		WithJobActor(jobActor).
		WithRequestStartedAt(requestctx.RequestStartedAtOrNow(ctx)).
		WithRunOptions(jobRunOpts).
		WithFeatures(features).
		WithProblemStatement(&problemStatement).
		WithAgentID(agenticApp.AppID()).
		WithEvent(jobservice.Event{
			Type:        eventType,
			URL:         req.EventURL,
			Identifiers: req.EventIdentifiers,
			Content:     req.EventContent,
		}).
		WithModel(req.Model).
		WithNewSession()

	if async {
		builder = builder.WithoutCreatingFeatures()
	}

	if !async {
		builder = builder.WithAINameGen().WithExperiments()
	}

	assignment, job, err := builder.Build(ctx, gh)

	return assignment, job, err
}

// GenerateCustomAgentQuote generates a markdown quote for a custom agent including
// its display name and description (if available). Returns an empty string for
// the default Copilot agent.
func GenerateCustomAgentQuote(agent sweagentd.CustomAgent) string {
	// We also want to include the subagent name in the PR body suffix
	customAgentQuote := ""
	// But only if it's not the default Copilot agent
	if _, isCopilot := agent.(*customagent.CopilotAgent); !isCopilot {
		agentName := agent.DisplayName()
		agentName = truncate(agentName, jobservice.MaxPullRequestBodyAgentNameLength)
		customAgentQuote = fmt.Sprintf(jobservice.PullRequestBodyAgentNameWrapper, agentName)

		agentDescription := agent.Description()
		if agentDescription != "" {
			agentDescription = fmt.Sprintf("> %s", strings.ReplaceAll(agentDescription, "\n", "\n> "))
			customAgentQuote += truncateAgentDescriptionWithLink(agentDescription, agent.RepoOwner(), agent.RepoName(), agent.Name(), jobservice.MaxPullRequestBodyAgentDescriptionLength)
			customAgentQuote += "\n"
		}
	}
	if customAgentQuote != "" {
		customAgentQuote += "\n"
	}
	return customAgentQuote
}

// constructOriginalPromptSection constructs the original prompt section that will be
// included in the problem statement. This contains the problem statement quote and
// custom agent details.
func constructOriginalPromptSection(problemStatementQuote, customAgentQuote string) string {
	content := problemStatementQuote + customAgentQuote
	if content == "" {
		return ""
	}
	return jobservice.PullRequestBodyOriginalPromptSeparator + content
}

// constructUserSuffixSection constructs the user-provided suffix section that will not
// be included in the problem statement. This contains user-provided content like "Fixes <Issue Number>".
func constructUserSuffixSection(userProvidedSuffix string) string {
	if userProvidedSuffix == "" {
		return ""
	}
	return jobservice.PullRequestBodySuffixSeparator + userProvidedSuffix
}

// ConstructResponseBodySuffix constructs the final ResponseBodySuffix by combining
// the problem statement quote, custom agent quote, and user-provided suffix with proper spacing.
func ConstructResponseBodySuffix(problemStatementQuote, customAgentQuote, userProvidedSuffix string) string {
	return jobservice.PullRequestBodySuffixSeparator + problemStatementQuote + customAgentQuote + userProvidedSuffix
}

// GenerateProblemStatementQuote generates a markdown quote for the problem statement
// wrapped in a collapsible details/summary block. Returns an empty string if the
// content is empty.
func GenerateProblemStatementQuote(content string) string {
	if content == "" {
		return ""
	}

	problemStatementQuote := content
	// We want to format the problem statement we include in the PR body as a
	// markdown quote, but also need to make sure the resulting value doesn't
	// exceed the maximum length designated for the problem statement after adding
	// the markdown quote characters (>).
	// If the initial problem statement is less than the maximum allowed length,
	// we attempt to quote it. If the result exceeds the max, we fall back to
	// truncating the original problem statement to fit within the max length.
	if utf8.RuneCountInString(problemStatementQuote) < jobservice.MaxPullRequestBodyProblemStatementQuoteLength {
		// try to quote the problem statement and see if it fits within the max length
		withMarkdown := fmt.Sprintf("> %s\n", strings.ReplaceAll(problemStatementQuote, "\n", "\n> "))
		if utf8.RuneCountInString(withMarkdown) < jobservice.MaxPullRequestBodyProblemStatementQuoteLength {
			// if the markdown version is within the max length, use it
			problemStatementQuote = withMarkdown
		}
	}

	// Again, length constraint should be handled by validation, but call truncate
	// just in case, then wrap it in the HTML details/summary tags to make it
	// collapsible in the PR body
	problemStatementQuote = truncate(problemStatementQuote, jobservice.MaxPullRequestBodyProblemStatementQuoteLength)
	problemStatementQuote = fmt.Sprintf(jobservice.PullRequestBodyProblemStatementQuoteWrapper, problemStatementQuote)

	return problemStatementQuote
}

// BuildEnvironmentFeatures constructs the jobs.EnvironmentFeatures structure based on
// the request features, pull request feature, and base ref.
//
// The logic handles three cases:
// 1. When an explicit Branch feature is provided, it is used directly.
// 2. When neither Branch nor PullRequest features are provided, a Pull Request is created by default.
// 3. When a PullRequest feature is provided, PullRequest is set and Branch is not set
//
//	(the PR handles its own branch creation).
func BuildEnvironmentFeatures(reqFeatures *EnvironmentFeatures, pullRequestFeature *PullRequestFeature) jobs.EnvironmentFeatures {
	features := jobs.EnvironmentFeatures{}

	// User explicitly provided pull request configuration
	if pullRequestFeature != nil {
		features.PullRequest = &jobs.PullRequestFeature{
			TitlePlaceholder: pullRequestFeature.Title,
			BodyPlaceholder:  pullRequestFeature.BodyPlaceholder,
			BodySuffix:       pullRequestFeature.BodySuffix,
			Labels:           pullRequestFeature.Labels,
			BaseRef:          pullRequestFeature.BaseRef,
			HeadRef:          pullRequestFeature.HeadRef,
		}
		return features
	}

	// No features provided in the request - create an empty PullRequest feature
	// to indicate a PR should be created
	if reqFeatures == nil {
		features.PullRequest = &jobs.PullRequestFeature{}
		return features
	}

	// User explicitly provided branch configuration
	if reqFeatures.Branch != nil {
		features.Branch = &jobs.BranchFeature{
			Name:    reqFeatures.Branch.Name,
			BaseRef: reqFeatures.Branch.BaseRef,
		}
		return features
	}

	// Features were requested, but neither PullRequest nor Branch features were provided.
	// Default to creating a PR.
	features.PullRequest = &jobs.PullRequestFeature{}
	return features
}

// determineBaseRef determines the base ref for the job based on the request features
// and the repository's default branch. It prioritizes the PullRequest base ref,
// then the Branch base ref, and finally falls back to the repository's default branch.
func determineBaseRef(req *NewJobAPIRequest, repo *gg.Repository) string {
	baseRef := fmt.Sprintf("refs/heads/%s", repo.GetDefaultBranch())
	if req.Features == nil {
		return baseRef
	}
	if req.Features.PullRequest != nil && req.Features.PullRequest.BaseRef != "" {
		return req.Features.PullRequest.BaseRef
	}
	if req.Features.Branch != nil && req.Features.Branch.BaseRef != "" {
		return req.Features.Branch.BaseRef
	}
	return baseRef
}
