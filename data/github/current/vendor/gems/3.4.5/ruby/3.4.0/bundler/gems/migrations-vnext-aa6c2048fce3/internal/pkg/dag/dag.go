// Package dag contains a directed acyclic graph implementation that
// understands MVN resources. This package is not intended to be a generic
// DAG implementation.
package dag

import (
	"context"
	"errors"
	"fmt"

	"github.com/github/migrations-vnext/internal/pkg/keys"
	"github.com/github/migrations-vnext/internal/pkg/set"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
)

const (
	// UnknownNode is the default node kind.
	UnknownNode NodeKind = iota
	// ResourceNode is a node that represents a resource in the DAG.
	ResourceNode
	// EventNode is a node that represents an event in the DAG.
	EventNode
)

type (
	// DAG is an interface for interacting with the DAG.
	DAG interface {
		AddNode(ctx context.Context, namespace string, kind NodeKind, id ID, dependencies ...Node) error
		EligibleNodes(ctx context.Context, namespace string) ([]Node, error)
		MarkAsProcessed(ctx context.Context, namespace string, nodes []Node) error
	}

	// NodeKind is an enum that represents the kind of node in the DAG.
	NodeKind int

	// Node is a struct that represents a node in the DAG.
	Node struct {
		ID   ID
		Kind NodeKind
	}

	// preparedResource is a struct that contains the information needed to
	// add a resource to the DAG and store its payload.
	preparedResource struct {
		ID      ID
		Deps    set.Set[ID]
		Payload *v1.Resource
	}
)

func prepResource(id string, payload *v1.Resource) (preparedResource, error) {
	if id == "" {
		return preparedResource{}, errors.New("empty id is not allowed")
	}
	return preparedResource{
		ID:      ID(id),
		Deps:    set.New[ID](),
		Payload: payload,
	}, nil
}

// AddDeps converts and adds a string ID to the preparedResource Deps set.
func (p preparedResource) AddDeps(ids ...string) error {
	for _, id := range ids {
		if id == "" {
			return errors.New("empty dep id is not allowed")
		}
		p.Deps.Add(ID(id))
	}
	return nil
}

// prepareResource takes a Resource and prepares it for insertion into
// the DAG. This preparation is focused on discovery and creation of
// dependencies.
//
//nolint:maintidx // this handles multiple resource types and their dependencies, making it inherently complex
func prepareResource(res *v1.Resource) ([]preparedResource, error) {
	var preparedResources []preparedResource
	switch r := res.Resource.(type) {
	case *v1.Resource_Organization:
		res, err := prepareOrganization(res, r.Organization)
		if err != nil {
			return nil, err
		}
		preparedResources = append(preparedResources, res)

	case *v1.Resource_InitialOrganizationSettings:
		res, err := prepareInitialOrganizationSettings(res, r.InitialOrganizationSettings)
		if err != nil {
			return nil, err
		}
		preparedResources = append(preparedResources, res)

	case *v1.Resource_Mannequin:
		res, err := prepareMannequin(res, r.Mannequin)
		if err != nil {
			return nil, err
		}
		preparedResources = append(preparedResources, res)

	case *v1.Resource_Team:
		preparedTeam, err := prepareTeam(res, r.Team)
		if err != nil {
			return nil, err
		}
		preparedResources = append(preparedResources, preparedTeam)

	case *v1.Resource_Repository:
		preparedRepo, err := prepareRepository(res, r.Repository)
		if err != nil {
			return nil, err
		}
		preparedResources = append(preparedResources, preparedRepo)
	case *v1.Resource_ProtectedBranch:
		preparedProtectedBranch, err := prepareProtectedBranch(res, r.ProtectedBranch)
		if err != nil {
			return nil, err
		}
		preparedResources = append(preparedResources, preparedProtectedBranch)
	case *v1.Resource_InitialRepositorySettings:
		preparedInitialRepoSettings, err := prepareInitialRepositorySettings(res, r.InitialRepositorySettings)
		if err != nil {
			return nil, err
		}
		preparedResources = append(preparedResources, preparedInitialRepoSettings)
	case *v1.Resource_InitialActionsSettings:
		preparedInitialActionsSettings, err := prepareInitialActionsSettings(res, r.InitialActionsSettings)
		if err != nil {
			return nil, err
		}
		preparedResources = append(preparedResources, preparedInitialActionsSettings)
	case *v1.Resource_Issue:
		preparedIssue, err := prepareIssue(res, r.Issue)
		if err != nil {
			return nil, err
		}
		preparedResources = append(preparedResources, preparedIssue)

	case *v1.Resource_IssueComment:
		preparedIssueComment, err := prepareIssueComment(res, r.IssueComment)
		if err != nil {
			return nil, err
		}
		preparedResources = append(preparedResources, preparedIssueComment)

	case *v1.Resource_IssueEventBatch:
		preparedIssueEventBatch, err := prepareIssueEventBatch(res, r.IssueEventBatch)
		if err != nil {
			return nil, err
		}
		preparedResources = append(preparedResources, preparedIssueEventBatch)

	case *v1.Resource_PullRequest:
		preparedPR, err := preparePullRequest(res, r.PullRequest)
		if err != nil {
			return nil, err
		}

		preparedResources = append(preparedResources, preparedPR)
	case *v1.Resource_PullRequestReview:
		preparedPullRequestReview, err := preparePullRequestReview(res, r.PullRequestReview)
		if err != nil {
			return nil, err
		}
		preparedResources = append(preparedResources, preparedPullRequestReview)

	case *v1.Resource_MilestoneBatch:
		res, err := prepareMilestoneBatch(res, r.MilestoneBatch)
		if err != nil {
			return nil, err
		}
		preparedResources = append(preparedResources, res)

	case *v1.Resource_Attachment:
		res, err := prepareAttachment(res, r.Attachment)
		if err != nil {
			return nil, err
		}
		preparedResources = append(preparedResources, res)

	case *v1.Resource_RepositoryLabelsBatch:
		res, err := prepareRepositoryLabelsBatch(res, r.RepositoryLabelsBatch)
		if err != nil {
			return nil, err
		}
		preparedResources = append(preparedResources, res...)

	case *v1.Resource_Project:
		res, err := prepareProject(res, r.Project)
		if err != nil {
			return nil, err
		}
		preparedResources = append(preparedResources, res)

	case *v1.Resource_ProjectColumn:
		res, err := prepareProjectColumn(res, r.ProjectColumn)
		if err != nil {
			return nil, err
		}
		preparedResources = append(preparedResources, res)

	case *v1.Resource_ProjectCardsBatch:
		res, err := prepareProjectCardsBatch(res, r.ProjectCardsBatch)
		if err != nil {
			return nil, err
		}
		preparedResources = append(preparedResources, res)

	case *v1.Resource_IssueLabelsBatch:
		res, err := prepareIssueLabelsBatch(res, r.IssueLabelsBatch)
		if err != nil {
			return nil, err
		}
		preparedResources = append(preparedResources, res)

	case *v1.Resource_CommitComment:
		preparedCommitComment, err := prepareCommitComment(res, r.CommitComment)
		if err != nil {
			return nil, err
		}
		preparedResources = append(preparedResources, preparedCommitComment)

	case *v1.Resource_ReactionsBatch:
		res, err := prepareReactionsBatch(res, r.ReactionsBatch)
		if err != nil {
			return nil, err
		}
		preparedResources = append(preparedResources, res)

	case *v1.Resource_CloseIssueReferenceBatch:
		res, err := prepareCloseIssueReferenceBatch(res, r.CloseIssueReferenceBatch)
		if err != nil {
			return nil, err
		}
		preparedResources = append(preparedResources, res...)
	case *v1.Resource_Release:
		res, err := prepareRelease(res, r.Release)
		if err != nil {
			return nil, err
		}
		preparedResources = append(preparedResources, res)
	case *v1.Resource_ReleaseAsset:
		res, err := prepareReleaseAsset(res, r.ReleaseAsset)
		if err != nil {
			return nil, err
		}
		preparedResources = append(preparedResources, res)
	default:
		return nil, fmt.Errorf("unknown resource type: %T", r)
	}

	return preparedResources, nil
}

func prepareOrganization(payload *v1.Resource, o *v1.Organization) (preparedResource, error) {
	return prepResource(o.ResourceId, payload)
}

func prepareInitialOrganizationSettings(payload *v1.Resource, settings *v1.InitialOrganizationSettings) (preparedResource, error) {
	res, err := prepResource(settings.ResourceId, payload)
	if err != nil {
		return preparedResource{}, err
	}
	// dependencies (org)
	if err := res.AddDeps(settings.OrganizationResourceId); err != nil {
		return preparedResource{}, err
	}
	return res, nil
}

func prepareMannequin(payload *v1.Resource, mannequin *v1.Mannequin) (preparedResource, error) {
	res, err := prepResource(mannequin.ResourceId, payload)
	if err != nil {
		return preparedResource{}, err
	}
	// dependencies (org)
	if err := res.AddDeps(mannequin.OrgResourceId); err != nil {
		return preparedResource{}, err
	}
	return res, nil
}

func prepareTeam(payload *v1.Resource, team *v1.Team) (preparedResource, error) {
	teamKey, err := keys.ToTeamKey(team.ResourceId)
	if err != nil {
		return preparedResource{}, fmt.Errorf("failed to parse team key: %w", err)
	}
	res, err := prepResource(team.ResourceId, payload)
	if err != nil {
		return preparedResource{}, err
	}
	// dependencies (org)
	if err := res.AddDeps(teamKey.OrganizationKey.String()); err != nil {
		return preparedResource{}, err
	}
	if team.ParentTeamResourceId != "" {
		// dependencies (parent team)
		if err := res.AddDeps(team.ParentTeamResourceId); err != nil {
			return preparedResource{}, err
		}
	}
	return res, nil
}

func prepareRepository(payload *v1.Resource, repo *v1.Repository) (preparedResource, error) {
	repoKey, err := keys.ToRepositoryKey(repo.ResourceId)
	if err != nil {
		return preparedResource{}, fmt.Errorf("failed to parse repository key: %w", err)
	}
	res, err := prepResource(repo.ResourceId, payload)
	if err != nil {
		return preparedResource{}, err
	}
	// dependencies (org)
	if err := res.AddDeps(repoKey.OrganizationKey.String()); err != nil {
		return preparedResource{}, err
	}
	return res, nil
}

func prepareProtectedBranch(payload *v1.Resource, protectedBranch *v1.ProtectedBranch) (preparedResource, error) {
	res, err := prepResource(protectedBranch.ResourceId, payload)
	if err != nil {
		return preparedResource{}, err
	}
	// dependencies (repo)
	if err := res.AddDeps(protectedBranch.RepositoryResourceId); err != nil {
		return preparedResource{}, err
	}
	return res, nil
}

func prepareInitialRepositorySettings(payload *v1.Resource, settings *v1.InitialRepositorySettings) (preparedResource, error) {
	repoKey, err := keys.ToRepositoryKey(settings.RepositoryResourceId)
	if err != nil {
		return preparedResource{}, fmt.Errorf("failed to parse repository key: %w", err)
	}
	res, err := prepResource(settings.ResourceId, payload)
	if err != nil {
		return preparedResource{}, err
	}
	// dependencies (repo, organizationsettings)
	orgSettingsKey := fmt.Sprintf("organizationsettings-%s", repoKey.OrganizationKey.String())
	if err := res.AddDeps(settings.RepositoryResourceId, orgSettingsKey); err != nil {
		return preparedResource{}, err
	}
	// dependencies (repository topic creators)
	for _, t := range settings.RepositoryTopics {
		if err := res.AddDeps(t.CreatorResourceId); err != nil {
			return preparedResource{}, err
		}
	}

	return res, nil
}

func prepareInitialActionsSettings(payload *v1.Resource, settings *v1.InitialActionsSettings) (preparedResource, error) {
	repoKey, err := keys.ToRepositoryKey(settings.RepositoryResourceId)
	if err != nil {
		return preparedResource{}, fmt.Errorf("failed to parse repository key: %w", err)
	}
	res, err := prepResource(settings.ResourceId, payload)
	if err != nil {
		return preparedResource{}, err
	}

	// dependencies (repo, organizationsettings)
	orgSettingsKey := fmt.Sprintf("organizationsettings-%s", repoKey.OrganizationKey.String())
	if err := res.AddDeps(settings.RepositoryResourceId, orgSettingsKey); err != nil {
		return preparedResource{}, err
	}
	return res, nil
}

func prepareIssue(payload *v1.Resource, issue *v1.Issue) (preparedResource, error) {
	issueKey, err := keys.ToIssueKey(issue.ResourceId)
	if err != nil {
		return preparedResource{}, fmt.Errorf("failed to parse issue key: %w", err)
	}
	res, err := prepResource(issue.ResourceId, payload)
	if err != nil {
		return preparedResource{}, err
	}
	// dependencies (repo, author, assignees, attachments)
	deps := []string{issueKey.RepositoryKey.String(), issue.UserResourceId}
	deps = append(deps, issue.AssigneesResourceIds...)
	deps = append(deps, issue.AttachmentResourceIds...)

	if err := res.AddDeps(deps...); err != nil {
		return preparedResource{}, err
	}

	return res, nil
}

func prepareIssueComment(payload *v1.Resource, comment *v1.IssueComment) (preparedResource, error) {
	commentKey, err := keys.ToIssueCommentKey(comment.ResourceId)
	if err != nil {
		return preparedResource{}, fmt.Errorf("failed to parse issue comment key: %w", err)
	}
	res, err := prepResource(comment.ResourceId, payload)
	if err != nil {
		return preparedResource{}, err
	}
	// dependencies (issue or pr, author, attachments)
	deps := []string{commentKey.IssueKey.String(), comment.UserResourceId}
	deps = append(deps, comment.AttachmentResourceIds...)
	if err := res.AddDeps(deps...); err != nil {
		return preparedResource{}, err
	}
	return res, nil
}

func prepareIssueEventBatch(payload *v1.Resource, batch *v1.IssueEventBatch) (preparedResource, error) {
	res, err := prepResource(batch.ResourceId, payload)
	if err != nil {
		return preparedResource{}, err
	}
	// dependencies (issues, actors, referenced prs, repositories)
	deps := []string{}
	deps = append(deps, batch.IssueResourceIds...)
	deps = append(deps, batch.UserResourceIds...)
	deps = append(deps, batch.PullRequestResourceIds...)
	deps = append(deps, batch.RepositoryResourceIds...)
	// dependencies (git pushed data for each repo)
	for _, repoID := range batch.RepositoryResourceIds {
		k, err := keys.ToRepositoryKey(repoID)
		if err != nil {
			return preparedResource{}, fmt.Errorf("failed to parse repository key: %w", err)
		}
		deps = append(deps, keys.GitDataResourceID(k))
	}

	if err := res.AddDeps(deps...); err != nil {
		return preparedResource{}, err
	}
	return res, nil
}

func preparePullRequest(payload *v1.Resource, pr *v1.PullRequest) (preparedResource, error) {
	prKey, err := keys.ToPullRequestKey(pr.ResourceId)
	if err != nil {
		return preparedResource{}, fmt.Errorf("failed to parse pull request key: %w", err)
	}
	res, err := prepResource(pr.ResourceId, payload)
	if err != nil {
		return preparedResource{}, err
	}
	// dependencies (repo, author, assignees, reviewers, attachments)
	deps := []string{prKey.RepositoryKey.String(), pr.UserResourceId}
	deps = append(deps, pr.AssigneesResourceIds...)
	deps = append(deps, pr.AttachmentResourceIds...)
	if err := res.AddDeps(deps...); err != nil {
		return preparedResource{}, err
	}
	return res, nil
}

func preparePullRequestReview(payload *v1.Resource, prRev *v1.PullRequestReview) (preparedResource, error) {
	prKey, err := keys.ToPullRequestReviewKey(prRev.ResourceId)
	if err != nil {
		return preparedResource{}, fmt.Errorf("failed to parse pr review key: %w", err)
	}
	res, err := prepResource(prRev.ResourceId, payload)
	if err != nil {
		return preparedResource{}, err
	}
	// dependencies (pr and author)
	deps := []string{prKey.PullRequestKey.String(), prRev.UserResourceId}
	if len(prRev.AttachmentResourceIds) > 0 {
		deps = append(deps, prRev.AttachmentResourceIds...)
	}
	// dependencies from comments (pr review comment authors, and other comments and threads)
	for _, comment := range prRev.Comments {
		deps = append(deps, comment.UserResourceId)
		if comment.InReplyToCommentResourceId != "" {
			deps = append(deps, comment.InReplyToCommentResourceId)
		}
		if comment.PullRequestReviewThreadResourceId != "" {
			deps = append(deps, comment.PullRequestReviewThreadResourceId)
		}
	}
	// dependencies from threads (user resolvers and comment authors)
	for _, thread := range prRev.Threads {
		if thread.ResolvedUserResourceId != "" {
			deps = append(deps, thread.ResolvedUserResourceId)
		}
		for _, comment := range thread.Comments {
			deps = append(deps, comment.UserResourceId)
		}
	}
	// dependencies on the git pushed data for the repo
	deps = append(deps, keys.GitDataResourceID(prKey.RepositoryKey))

	if err := res.AddDeps(deps...); err != nil {
		return preparedResource{}, err
	}
	return res, nil
}

func prepareMilestoneBatch(payload *v1.Resource, batch *v1.MilestoneBatch) (preparedResource, error) {
	res, err := prepResource(batch.ResourceId, payload)
	if err != nil {
		return preparedResource{}, err
	}
	// dependencies (issues, users)
	deps := []string{}
	deps = append(deps, batch.IssueResourceIds...)
	deps = append(deps, batch.UserResourceIds...)
	if err := res.AddDeps(deps...); err != nil {
		return preparedResource{}, err
	}
	return res, nil
}

func prepareAttachment(payload *v1.Resource, attachment *v1.Attachment) (preparedResource, error) {
	res, err := prepResource(attachment.ResourceId, payload)
	if err != nil {
		return preparedResource{}, err
	}
	if err := res.AddDeps(attachment.RepositoryId); err != nil {
		return preparedResource{}, err
	}
	return res, nil
}

func prepareRepositoryLabelsBatch(payload *v1.Resource, batch *v1.RepositoryLabelsBatch) ([]preparedResource, error) {
	batchRes, err := prepResource(batch.ResourceId, payload)
	if err != nil {
		return nil, err
	}
	// dependencies (repo)
	if err := batchRes.AddDeps(batch.RepositoryId); err != nil {
		return nil, err
	}

	// Also add each label to the dag. As individual resources
	// they may be depended on, but they will not be processed
	// individually.
	var labelRes []preparedResource
	for _, label := range batch.Labels {
		res, err := prepResource(label.ResourceId,
			&v1.Resource{Resource: &v1.Resource_Noop{
				Noop: &v1.Noop{ResourceId: label.ResourceId},
			}, MigrationContext: payload.MigrationContext})
		if err != nil {
			return nil, err
		}
		if err := res.AddDeps(batch.ResourceId); err != nil {
			return nil, err
		}
		labelRes = append(labelRes, res)
	}
	return append(labelRes, batchRes), nil
}

func prepareProject(payload *v1.Resource, project *v1.Project) (preparedResource, error) {
	res, err := prepResource(project.ResourceId, payload)
	if err != nil {
		return preparedResource{}, err
	}
	if err := res.AddDeps(project.OwnerResourceId); err != nil {
		return preparedResource{}, err
	}
	if project.CreatorResourceId != project.OwnerResourceId {
		if err := res.AddDeps(project.CreatorResourceId); err != nil {
			return preparedResource{}, err
		}
	}
	return res, nil
}

func prepareProjectColumn(payload *v1.Resource, column *v1.ProjectColumn) (preparedResource, error) {
	res, err := prepResource(column.ResourceId, payload)
	if err != nil {
		return preparedResource{}, err
	}

	deps := []string{column.ProjectResourceId}
	for _, workflow := range column.Workflows {
		deps = append(deps, workflow.CreatorResourceId)
		if workflow.LastUpdaterResourceId != "" {
			deps = append(deps, workflow.LastUpdaterResourceId)
		}
		for _, action := range workflow.Actions {
			deps = append(deps, action.CreatorResourceId)
			if action.LastUpdaterResourceId != "" {
				deps = append(deps, action.LastUpdaterResourceId)
			}
		}
	}

	if err := res.AddDeps(deps...); err != nil {
		return preparedResource{}, err
	}
	return res, nil
}

func prepareProjectCardsBatch(payload *v1.Resource, batch *v1.ProjectCardsBatch) (preparedResource, error) {
	res, err := prepResource(batch.ResourceId, payload)
	if err != nil {
		return preparedResource{}, err
	}
	deps := []string{batch.ProjectColumnResourceId}
	for _, card := range batch.Cards {
		if card.ContentResourceId != "" {
			deps = append(deps, card.ContentResourceId)
		}
	}
	if err := res.AddDeps(deps...); err != nil {
		return preparedResource{}, err
	}
	return res, nil
}

func prepareIssueLabelsBatch(payload *v1.Resource, batch *v1.IssueLabelsBatch) (preparedResource, error) {
	res, err := prepResource(batch.ResourceId, payload)
	if err != nil {
		return preparedResource{}, err
	}
	deps := []string{batch.IssueResourceId}
	deps = append(deps, batch.LabelResourceIds...)
	if err := res.AddDeps(deps...); err != nil {
		return preparedResource{}, err
	}
	return res, nil
}
func prepareCommitComment(payload *v1.Resource, comment *v1.CommitComment) (preparedResource, error) {
	commentKey, err := keys.ToCommitCommentKey(comment.ResourceId)
	if err != nil {
		return preparedResource{}, fmt.Errorf("failed to parse commit comment key: %w", err)
	}
	res, err := prepResource(comment.ResourceId, payload)
	if err != nil {
		return preparedResource{}, err
	}
	if err := res.AddDeps(commentKey.RepositoryKey.String(), keys.GitDataResourceID(commentKey.RepositoryKey), comment.UserResourceId); err != nil {
		return preparedResource{}, err
	}

	return res, nil
}

func prepareReactionsBatch(payload *v1.Resource, batch *v1.ReactionsBatch) (preparedResource, error) {
	res, err := prepResource(batch.ResourceId, payload)
	if err != nil {
		return preparedResource{}, err
	}

	deps := []string{batch.SubjectResourceId}
	for _, reaction := range batch.Reactions {
		deps = append(deps, reaction.UserResourceId)
	}
	if err := res.AddDeps(deps...); err != nil {
		return preparedResource{}, err
	}
	return res, nil
}

func prepareCloseIssueReferenceBatch(payload *v1.Resource, batch *v1.CloseIssueReferenceBatch) ([]preparedResource, error) {
	batchRes, err := prepResource(batch.ResourceId, payload)
	if err != nil {
		return nil, err
	}
	// dependent on all referenced issues and prs
	deps := []string{}
	virtualRefs := set.New[string]()
	for _, b := range batch.CloseIssueReferences {
		deps = append(deps, b.PullRequestResourceId, b.IssueResourceId)
		virtualRefs.Add(b.ResourceId)
	}
	if err := batchRes.AddDeps(deps...); err != nil {
		return nil, err
	}

	var refRes []preparedResource

	// We need to add references to the dag to track resolution of individual refs.
	// Since we process batches only, they are only virtual resources.
	for _, ref := range virtualRefs.ToSlice() {
		// The payload is a noop, as the actual ref is handled in the batch
		res, err := prepResource(ref,
			&v1.Resource{Resource: &v1.Resource_Noop{Noop: &v1.Noop{ResourceId: ref}}, MigrationContext: payload.MigrationContext})
		if err != nil {
			return nil, err
		}
		if err := res.AddDeps(batch.ResourceId); err != nil {
			return nil, err
		}
	}
	return append(refRes, batchRes), nil
}

func prepareRelease(payload *v1.Resource, release *v1.Release) (preparedResource, error) {
	res, err := prepResource(release.ResourceId, payload)
	if err != nil {
		return preparedResource{}, err
	}
	k, err := keys.ToRepositoryKey(release.RepositoryResourceId)
	if err != nil {
		return preparedResource{}, fmt.Errorf("failed to parse repository key: %w", err)
	}

	// dependencies (repository, author, git data pushed)
	if err := res.AddDeps(release.RepositoryResourceId, release.UserResourceId, keys.GitDataResourceID(k)); err != nil {
		return preparedResource{}, err
	}
	return res, nil
}

func prepareReleaseAsset(payload *v1.Resource, releaseAsset *v1.ReleaseAsset) (preparedResource, error) {
	res, err := prepResource(releaseAsset.ResourceId, payload)
	if err != nil {
		return preparedResource{}, err
	}
	// dependencies (release, author)
	if err := res.AddDeps(releaseAsset.ReleaseResourceId, releaseAsset.UserResourceId); err != nil {
		return preparedResource{}, err
	}
	return res, nil
}

func prepareEventDeps(event *v1.Event) (set.Set[ID], error) {
	var err error
	var deps set.Set[ID]
	switch event.EventDetails.(type) {
	case *v1.Event_IssueEvent:
		deps, err = prepareIssueEventDeps(event)
	case *v1.Event_IssueCommentEvent:
		deps, err = prepareIssueCommentEventDeps(event)
	case *v1.Event_PullRequestEvent:
		deps, err = preparePullRequestEventDeps(event)
	case *v1.Event_PullRequestReviewEvent:
		deps, err = preparePullRequestReviewEventDeps(event)
	case *v1.Event_PullRequestReviewCommentEvent:
		deps, err = preparePullRequestReviewCommentEventDeps(event)
	case *v1.Event_PullRequestReviewThreadEvent:
		deps, err = preparePullRequestReviewThreadEventDeps(event)
	default:
		return nil, fmt.Errorf("unknown event type to prepare deps: %T", event.EventDetails)
	}
	if err != nil {
		return nil, fmt.Errorf("error preparing event of type %T deps for insertion into dag: %w", event.EventDetails, err)
	}
	for _, dep := range deps.ToSlice() {
		if dep == "" {
			return nil, fmt.Errorf("empty dependency found for event type %T %s", event.EventDetails, event.EventId)
		}
	}
	return deps, nil
}

func prepareIssueEventDeps(event *v1.Event) (set.Set[ID], error) {
	issue := event.GetIssueEvent()
	res, err := prepareIssue(&v1.Resource{}, issue)
	if err != nil {
		return nil, fmt.Errorf("error preparing issue event for insertion into dag: %w", err)
	}
	return res.Deps, nil
}

func prepareIssueCommentEventDeps(event *v1.Event) (set.Set[ID], error) {
	comment := event.GetIssueCommentEvent()
	res, err := prepareIssueComment(&v1.Resource{}, comment)
	if err != nil {
		return nil, fmt.Errorf("error preparing issue comment event for insertion into dag: %w", err)
	}
	return res.Deps, nil
}

func preparePullRequestEventDeps(event *v1.Event) (set.Set[ID], error) {
	pr := event.GetPullRequestEvent()
	res, err := preparePullRequest(&v1.Resource{}, pr)
	if err != nil {
		return nil, fmt.Errorf("error preparing pull request event for insertion into dag: %w", err)
	}
	return res.Deps, nil
}

func preparePullRequestReviewEventDeps(event *v1.Event) (set.Set[ID], error) {
	prRev := event.GetPullRequestReviewEvent()
	return set.New[ID](ID(prRev.UserResourceId)), nil
}

func preparePullRequestReviewCommentEventDeps(event *v1.Event) (set.Set[ID], error) {
	prRevComment := event.GetPullRequestReviewCommentEvent()
	return set.New[ID](ID(prRevComment.UserResourceId)), nil
}

func preparePullRequestReviewThreadEventDeps(event *v1.Event) (set.Set[ID], error) {
	prRevThread := event.GetPullRequestReviewThreadEvent()
	return set.New[ID](ID(prRevThread.UserResourceId)), nil
}

// String implements the Stringer interface for NodeKind.
func (n NodeKind) String() string {
	switch n {
	case ResourceNode:
		return "ResourceNode"
	case EventNode:
		return "EventNode"
	default:
		return "UnknownNode"
	}
}

// NodeKindFromString converts a string to a NodeKind. If the string is not
// recognized, it returns UnknownNode.
func NodeKindFromString(s string) NodeKind {
	switch s {
	case "ResourceNode":
		return ResourceNode
	case "EventNode":
		return EventNode
	default:
		return UnknownNode
	}
}
