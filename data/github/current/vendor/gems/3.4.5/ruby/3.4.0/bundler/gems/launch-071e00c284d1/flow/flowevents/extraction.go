package flowevents

import (
	"time"

	"github.com/google/go-github/v25/github"
	errs "github.com/pkg/errors"

	"github.com/github/launch/types"
)

// DO NOT remove event types from this list without explicit review from
// @github/appsec
//
// See https://github.com/github/c2c-actions/issues/255 for context.
var eventTypesForDefaultBranch = map[string]struct{}{
	"branch_protection_rule": {},
	"check_run":              {},
	"check_suite":            {},
	"delete":                 {},
	"discussion":             {},
	"discussion_comment":     {},
	"fork":                   {},
	"gollum":                 {},
	"interactive_component":  {},
	"issue_comment":          {},
	"issues":                 {},
	"label":                  {},
	"marketplace_purchase":   {},
	"member":                 {},
	"milestone":              {},
	"page_build":             {},
	"project_card":           {},
	"project_column":         {},
	"project":                {},
	"public":                 {},
	"repository_dispatch":    {},
	"status":                 {},
	"watch":                  {},
	"workflow_run":           {},
}

// ExtractCommitAndRef extracts commit/branch reference from event.
// Returns the commit sha, the ref, a boolean indicating if the event is
// supported i.e. a workflow run should be queued for it, and an error.
func ExtractCommitAndRef(eventType string, gitHubEvent GitHubEvent) (types.CommitSha, types.GitRef, bool, error) {
	// Some events don't reference a commit:
	if _, useDefaultBranch := eventTypesForDefaultBranch[eventType]; useDefaultBranch {
		return types.CommitShaZeroValue, types.DefaultBranch, true, nil
	}

	switch e := gitHubEvent.(type) {
	case *github.CreateEvent:
		refType := e.GetRefType()
		switch refType {
		case "branch":
			return types.CommitShaZeroValue, types.NewBranchRef(e.GetRef()), true, nil
		case "tag":
			return types.CommitShaZeroValue, types.NewTagRef(e.GetRef()), true, nil
		default:
			return types.CommitShaZeroValue, types.GitRefZeroValue, false, errs.Errorf("unsupported ref type %s", refType)
		}
	case HasDeployment:
		ref := e.GetDeployment().GetRef()
		var gitRef types.GitRef
		if types.IsCommitSha(ref) {
			gitRef = types.GitRefZeroValue
		} else {
			// TODO Undetermined ref type
			gitRef = types.GitRef(ref)
		}
		return types.CommitSha(e.GetDeployment().GetSHA()), gitRef, true, nil
	case HasPullRequest:
		return extractPRCommitAndRef(e)
	case *github.MergeGroupEvent:
		return types.CommitSha(e.GetMergeGroup().GetHeadSHA()), types.GitRef(e.GetMergeGroup().GetHeadRef()), true, nil
	case *github.PushEvent:
		// If the `after` OID is the null sha, the ref was removed
		if types.CommitSha(e.GetAfter()).IsNullSha() {
			return types.CommitShaZeroValue, types.DefaultBranch, true, nil
		}

		headCommit := e.GetHeadCommit()
		if headCommit == nil {
			// All events with a non-null `after` OID are expected to have a
			// `head_commit`. `head_commit` may be null if a ref points to an
			// object that is not a commit or another ref that eventually
			// points to a commit. This is not an extraction error but we
			// should not queue a workflow run for similar events.
			// https://github.com/github/actions-relaunch/issues/930
			return types.CommitShaZeroValue, types.GitRefZeroValue, false, nil
		}

		return types.CommitSha(headCommit.GetID()), types.GitRef(e.GetRef()), true, nil
	case *github.RegistryPackageEvent:
		return types.CommitSha(e.RegistryPackage.PackageVersion.TargetOid), types.GitRef(e.RegistryPackage.PackageVersion.TargetCommitish), true, nil
	case *github.ReleaseEvent:
		return types.CommitShaZeroValue, types.NewTagRef(e.GetRelease().GetTagName()), true, nil
	case *github.WorkflowDispatchEvent:
		return types.CommitShaZeroValue, types.GitRef(e.GetRef()), true, nil
	case *DynamicEvent:
		return types.CommitShaZeroValue, types.GitRef(e.Ref), true, nil
	case *WorkflowCallEvent:
		// purposefully not handled as it should not be a real event
	}
	return types.CommitShaZeroValue, types.GitRefZeroValue, false, errs.New("could not extract commit")
}

func extractPRCommitAndRef(e HasPullRequest) (types.CommitSha, types.GitRef, bool, error) {
	eventRepoID := e.GetRepo().GetID()
	// baseBranch is the original branch, the one that you want to update with this pull request. Typically this will be master in the main repository.
	baseBranch := e.GetPullRequest().GetBase()
	baseRepoID := baseBranch.GetRepo().GetID()
	// headBranch is where the proposed changes are. It can be in the same repo as the baseBranch or in a fork.
	headBranch := e.GetPullRequest().GetHead()

	if eventRepoID == 0 || baseRepoID == 0 {
		// Our parsed payload isn't right.
		// This should not happen. But if it does, the rest of the comparisons
		// won't be valid, and we should fail closed to avoid leaking base repo
		// secrets via a PR from a fork.
		return types.CommitShaZeroValue, types.GitRefZeroValue, false, errs.New(".repository and .pull_request.base.repo must both have IDs!")
	}

	if baseRepoID != eventRepoID {
		// The base branch is not in the repo that the hook was sent for.
		// This should never happen. But if it does, fail closed. ❌
		return types.CommitShaZeroValue, types.GitRefZeroValue, false, errs.New("Event fired for wrong repo?")
	}

	// we run workflows found on the tip of the PR's branch.
	hc := types.CommitSha(headBranch.GetSHA())
	hr := types.NewBranchRef(headBranch.GetRef())

	if hc.IsZeroValue() {
		return types.CommitShaZeroValue, types.GitRefZeroValue, false, errs.New("head commit cannot be nil")
	}
	if hr.IsZeroValue() {
		return types.CommitShaZeroValue, types.GitRefZeroValue, false, errs.New("head ref cannot be nil")
	}
	return hc, hr, true, nil
}

type HasPullRequest interface {
	GetRepo() *github.Repository
	GetPullRequest() *github.PullRequest
}

type HasDeployment interface {
	GetDeployment() *github.Deployment
}

type HasIssue interface {
	GetIssue() *github.Issue
}

type HasBeforeAndAfter interface {
	GetBefore() string
	GetAfter() string
}

// ExtractEventTime extracts the pushedAt time from push events
func ExtractEventTime(eventType string, gitHubEvent GitHubEvent) time.Time {
	// Only push events have this
	if eventType != "push" {
		return time.Time{}
	}

	e := gitHubEvent.(*github.PushEvent)

	return e.GetRepo().GetPushedAt().Time
}

// ExtractEventAction extracts the action from an event if it exists
func ExtractEventAction(event GitHubEvent) string {
	if eventWithAction, ok := event.(Actionable); ok {
		return eventWithAction.GetAction()
	}
	return ""
}

// ExtractCommitMessage extracts a commit message from event, if it exists.
func ExtractCommitMessage(gitHubEvent GitHubEvent) types.CommitMessage {
	switch e := gitHubEvent.(type) {
	case *github.PushEvent:
		// no message if it's a delete push event
		if types.CommitSha(e.GetAfter()).IsNullSha() {
			return types.CommitMessageZeroValue
		}
		if e.HeadCommit != nil && e.HeadCommit.Message != nil {
			return types.CommitMessage(*e.HeadCommit.Message)
		}
	}
	return types.CommitMessageZeroValue
}
