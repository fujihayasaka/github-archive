// Package client contains interfaces and implementations for importing resources using Octoshift Import API types.
package client

import (
	"context"

	v1 "github.com/github/migrations-vnext/internal/pkg/octoshift/imports/v1"
)

// Importer is an interface that defines the methods that are required to use the internal Twirp
// API for importing resources
//
//nolint:interfacebloat // This is arbitrary, and arbitrarily refactoring is wasteful.
type Importer interface {
	FindMannequin(ctx context.Context, in *v1.FindMannequinRequest) (*v1.FindMannequinResponse, error)
	CreateMannequin(ctx context.Context, in *v1.CreateMannequinRequest) (*v1.CreateMannequinResponse, error)
	ImportOrganization(ctx context.Context, in *v1.ImportOrganizationRequest) (*v1.ImportOrganizationResponse, error)
	ImportTeam(ctx context.Context, in *v1.ImportTeamRequest) (*v1.ImportTeamResponse, error)
	ImportRepository(ctx context.Context, in *v1.ImportRepositoryRequest) (*v1.ImportRepositoryResponse, error)
	ImportProtectedBranch(ctx context.Context, in *v1.ImportProtectedBranchRequest) (*v1.ImportProtectedBranchResponse, error)
	ImportReactions(ctx context.Context, in *v1.ImportReactionsRequest) (*v1.ImportReactionsResponse, error)
	ImportIssueComment(ctx context.Context, in *v1.ImportIssueCommentRequest) (*v1.ImportIssueCommentResponse, error)
	ImportTimelineEvent(ctx context.Context, in *v1.ImportTimelineEventsRequest) (*v1.ImportTimelineEventsResponse, error)
	ImportIssue(ctx context.Context, in *v1.ImportIssueRequest) (*v1.ImportIssueResponse, error)
	ImportMilestones(ctx context.Context, in *v1.ImportMilestonesRequest) (*v1.ImportMilestonesResponse, error)
	ImportPullRequest(ctx context.Context, in *v1.ImportPullRequestRequest) (*v1.ImportPullRequestResponse, error)
	ImportPullRequestReview(ctx context.Context, in *v1.ImportPullRequestReviewRequest) (*v1.ImportPullRequestReviewResponse, error)
	CreateAssetStoragePolicy(ctx context.Context, in *v1.CreateAssetStoragePolicyRequest) (*v1.CreateAssetStoragePolicyResponse, error)
	ImportLabels(ctx context.Context, in *v1.ImportLabelsRequest) (*v1.ImportLabelsResponse, error)
	AddLabelsToIssue(ctx context.Context, in *v1.AddLabelsToIssueRequest) (*v1.AddLabelsToIssueResponse, error)
	ImportRelease(ctx context.Context, in *v1.ImportReleaseRequest) (*v1.ImportReleaseResponse, error)
	ImportProject(ctx context.Context, in *v1.ImportProjectRequest) (*v1.ImportProjectResponse, error)
	ImportCommitComment(context.Context, *v1.ImportCommitCommentRequest) (*v1.ImportCommitCommentResponse, error)
	ImportProjectColumn(ctx context.Context, in *v1.ImportProjectColumnRequest) (*v1.ImportProjectColumnResponse, error)
	ImportProjectCards(ctx context.Context, in *v1.ImportProjectCardsRequest) (*v1.ImportProjectCardsResponse, error)
	ImportCloseIssueReferences(ctx context.Context, in *v1.ImportCloseIssueReferencesRequest) (*v1.ImportCloseIssueReferencesResponse, error)
	UpdateRepository(ctx context.Context, in *v1.UpdateRepositoryRequest) (*v1.UpdateRepositoryResponse, error)
	ImportOrganizationSettings(ctx context.Context, in *v1.ImportOrganizationSettingsRequest) (*v1.ImportOrganizationSettingsResponse, error)
	UpdateActionsSettings(ctx context.Context, in *v1.UpdateActionsSettingsRequest) (*v1.UpdateActionsSettingsResponse, error)
	EditIssue(ctx context.Context, in *v1.EditIssueRequest) (*v1.EditIssueResponse, error)
	EditIssueComment(ctx context.Context, in *v1.EditIssueCommentRequest) (*v1.EditIssueCommentResponse, error)
	EditPullRequest(ctx context.Context, in *v1.EditPullRequestRequest) (*v1.EditPullRequestResponse, error)
	EditPullRequestReview(ctx context.Context, in *v1.EditPullRequestReviewRequest) (*v1.EditPullRequestReviewResponse, error)
	EditPullRequestReviewThread(ctx context.Context, in *v1.EditPullRequestReviewThreadRequest) (*v1.EditPullRequestReviewThreadResponse, error)
	EditPullRequestReviewComment(ctx context.Context, in *v1.EditPullRequestReviewCommentRequest) (*v1.EditPullRequestReviewCommentResponse, error)
}
