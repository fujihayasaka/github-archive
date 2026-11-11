// Package tips provides functionality to manage and retrieve tips for users based on feature flags.
package tips

import (
	"context"
	"math/rand"
	"strings"

	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/onboarding"
	"github.com/github/sweagentd/internal/sweagentd"
	gg "github.com/google/go-github/v75/github"
)

// PullRequestBodyTipSeparator separates the main body of the pull request
const PullRequestBodyTipSeparator string = "\n\n<!-- START COPILOT CODING AGENT TIPS -->\n---\n\n"

// GetRandomTipForJob returns a random enabled tip for the given job, or an empty string if no tips are enabled.
func GetRandomTipForJob(
	ctx context.Context,
	ffClient featureflags.Client,
	job *jobs.Job,
	repo *gg.Repository) string {
	if !ffClient.IsEnabledForUserOrRepoOrOwner(ctx, "copilot_swe_agent_tips", job) {
		return ""
	}

	tips := GetEnabledTips(ctx, ffClient, job, repo.Owner.GetLogin(), repo.GetName())
	if len(tips) == 0 {
		return ""
	}

	randomIndex := rand.Intn(len(tips)) //nolint:gosec // G404: Use of weak random number generator
	return tips[randomIndex]
}

type owner interface {
	GetID() int64
	GetLogin() string
}
type repo interface {
	GetID() int64
	GetName() string
}

type actors struct {
	repoID  int64
	ownerID int64
	actorID int64
}

func (a *actors) GetActorID() int64      { return a.actorID }
func (a *actors) GetRepositoryID() int64 { return a.repoID }
func (a *actors) GetOwnerID() int64      { return a.ownerID }

// GetRandomTipForJobByRepo returns a random enabled tip for the given actor, owner, and repo, or an empty string if no tips are enabled.
func GetRandomTipForJobByRepo(
	ctx context.Context,
	ffClient featureflags.Client,
	actor int64,
	owner owner,
	repo repo) string {
	actors := &actors{
		repoID:  repo.GetID(),
		ownerID: owner.GetID(),
		actorID: actor,
	}

	if !ffClient.IsEnabledForUserOrRepoOrOwner(ctx, "copilot_swe_agent_tips", actors) {
		return ""
	}

	tips := GetEnabledTips(ctx, ffClient, actors, owner.GetLogin(), repo.GetName())
	if len(tips) == 0 {
		return ""
	}

	randomIndex := rand.Intn(len(tips)) //nolint:gosec // G404: Use of weak random number generator
	return tips[randomIndex]
}

// Tip represents one tip with its associated feature flag name.
type Tip struct {
	Flag    string
	Content string
}

// GetAllTips returns all available tips with their associated feature flag names.
func GetAllTips() []Tip {
	return []Tip{
		{Flag: "copilot_swe_agent_tips_advanced_security", Content: github.AdvancedSecurityTip},
		{Flag: "copilot_swe_agent_tips_best_practices", Content: github.BestPracticesTip},
		{Flag: "copilot_swe_agent_tips_feedback", Content: github.FeedbackTip},
		{Flag: "copilot_swe_agent_tips_ide", Content: github.IDETip},
		{Flag: "copilot_swe_agent_tips_mobile", Content: github.MobileTip},
		{Flag: "copilot_swe_agent_tips_onboarding", Content: onboarding.OnboardingTip},
		{Flag: "copilot_swe_agent_tips_planning_and_tracking", Content: github.PlanningAndTrackingTip},
		{Flag: "copilot_swe_agent_tips_raycast", Content: github.RaycastTip},
		{Flag: "copilot_swe_agent_tips_workplace_chat", Content: github.WorkplaceChatTip},
	}
}

// RemoveTips removes the Copilot tips section from the given pull request body, if present
func RemoveTips(pullRequestBody string) string {
	if strings.Contains(pullRequestBody, PullRequestBodyTipSeparator) {
		parts := strings.Split(pullRequestBody, PullRequestBodyTipSeparator)
		if len(parts) > 1 {
			return parts[0]
		}
	}
	return pullRequestBody
}

// GetEnabledTips returns the list of enabled tips for the given actors and repo.
func GetEnabledTips(
	ctx context.Context,
	ffClient featureflags.Client,
	actors sweagentd.RepositoryWithActor,
	repoOwner string,
	repoName string) []string {
	tips := make([]string, 0)

	for _, tip := range GetAllTips() {
		if ffClient.IsEnabledForUserOrRepoOrOwner(ctx, tip.Flag, actors) {
			// Skip tips requiring repo parameters if they are missing.
			content, err := onboarding.SubstituteJobParameters(tip.Content, repoOwner, repoName)
			if err == nil {
				tips = append(tips, content)
			}
		}
	}

	return tips
}
