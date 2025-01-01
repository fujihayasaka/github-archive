package flowevents

import (
	"errors"

	"github.com/github/launch/clients/hydro/metadata"

	githubgo "github.com/google/go-github/v25/github"
	"github.com/shurcooL/githubv4"
)

const memberAssociation = string(githubv4.CommentAuthorAssociationMember)
const ownerAssociation = string(githubv4.CommentAuthorAssociationOwner)
const collaboratorAssociation = string(githubv4.CommentAuthorAssociationCollaborator)
const contributorAssociation = string(githubv4.CommentAuthorAssociationContributor)

// The various events in go-github unfortunately have no method present on every
// event. This is used in place of any in arguments etc, but provides no more type-safety.
// Go treats empty interfaces as identical and doesn't require explicit type conversions across them.
type GitHubEvent any

// Actionable is an event that has a `GetAction()` method
type Actionable interface {
	GetAction() string
}

// ActionableWorkflow is an event that has a `GetWorkflow()` method
type ActionableWorkflow interface {
	GetWorkflow() *githubgo.Workflow
}

// IsDependabotActor determines whether the given actor is Dependabot
// Note: This can return false when `actions_disable_dependabot_enforcement` is enabled (see https://github.com/github/c2c-actions/blob/master/docs/adrs/2875-addressing-customers-reactions-to-dependabot-limitations.md#option-d-feature-flag-to-opt-out-of-permissions-and-secrets)
func IsDependabotActor(actor *metadata.WorkflowMetadataActor) bool {
	return actor != nil && actor.IsDependabot
}

// IsForkPR returns whether or not the given PR is a fork
func IsForkPR(pr HasPullRequest) bool {
	// we deduce if this is a fork in this way
	// so we can allow a forked repo to use its
	// own secrets even though it is a fork.
	baseRepo := pr.GetPullRequest().GetBase().GetRepo()
	headRepo := pr.GetPullRequest().GetHead().GetRepo()

	return baseRepo.GetID() != headRepo.GetID()
}

// IsRestrictedForkPREvent determines if an event is a pull request event from a fork, excludes PullRequestTarget
func IsRestrictedForkPREvent(event string, ghe GitHubEvent) bool {
	// This isn't a pullrequest based event? Not in fork
	pr, isPullRequestBasedEvent := ghe.(HasPullRequest)
	if !isPullRequestBasedEvent {
		return false
	}

	if event == PullRequestTarget {
		return false
	}

	return IsForkPR(pr)
}

// PullRequestActorEligible determines if an author of a PR is eligible for automatic workflow runs
func PullRequestAuthorEligible(association string) bool {
	switch association {
	case memberAssociation, ownerAssociation, collaboratorAssociation, contributorAssociation:
		return true
	}
	return false
}

// GetPullRequestNumber safely returns the PR number from a *GitHubEvent
func GetPullRequestNumber(ghe GitHubEvent) (*int, error) {
	pr, ok := ghe.(HasPullRequest)
	if !ok {
		return nil, errors.New("event is not of type pull_request")
	}
	if pr.GetPullRequest().Number == nil {
		return nil, errors.New("pull_request event has no pull request number")
	}
	return pr.GetPullRequest().Number, nil
}
