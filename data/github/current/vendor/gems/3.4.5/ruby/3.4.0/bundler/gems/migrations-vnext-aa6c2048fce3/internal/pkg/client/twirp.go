package client

import (
	"context"

	v1 "github.com/github/migrations-vnext/internal/pkg/octoshift/imports/v1"
	"github.com/twitchtv/twirp"
)

// ImportClient wraps clients used to import resources into a backend.
type ImportClient struct {
	baseURL    string
	httpClient v1.HTTPClient
	opts       []twirp.ClientOption
}

// Ensure ImportClient implements the `Importer` interface.
var _ Importer = &ImportClient{}

// NewImportClient returns a client that exposes functionality for importing resources into
// a backend that implements the Octoshift imports Twirp API.
func NewImportClient(baseURL string, httpClient v1.HTTPClient, opts ...twirp.ClientOption) *ImportClient {
	return &ImportClient{
		httpClient: httpClient,
		baseURL:    baseURL,
		opts:       opts,
	}
}

// CreateMannequin creates a mannequin for an imported user.
func (c *ImportClient) CreateMannequin(ctx context.Context, in *v1.CreateMannequinRequest) (*v1.CreateMannequinResponse, error) {
	api := v1.NewMannequinAPIJSONClient(c.baseURL, c.httpClient, c.opts...)
	return api.CreateMannequin(ctx, in)
}

// FindMannequin finds an already created mannequin for an imported user.
func (c *ImportClient) FindMannequin(ctx context.Context, in *v1.FindMannequinRequest) (*v1.FindMannequinResponse, error) {
	api := v1.NewMannequinAPIJSONClient(c.baseURL, c.httpClient, c.opts...)
	return api.FindMannequin(ctx, in)
}

// ImportOrganization imports an organization for an imported org.
func (c *ImportClient) ImportOrganization(ctx context.Context, in *v1.ImportOrganizationRequest) (*v1.ImportOrganizationResponse, error) {
	api := v1.NewImportOrganizationAPIJSONClient(c.baseURL, c.httpClient, c.opts...)
	return api.ImportOrganization(ctx, in)
}

// ImportTeam imports an Team for an imported org.
func (c *ImportClient) ImportTeam(ctx context.Context, in *v1.ImportTeamRequest) (*v1.ImportTeamResponse, error) {
	api := v1.NewImportTeamAPIJSONClient(c.baseURL, c.httpClient, c.opts...)
	return api.ImportTeam(ctx, in)
}

// ImportRepository imports a repository for an imported repository.
func (c *ImportClient) ImportRepository(ctx context.Context, in *v1.ImportRepositoryRequest) (*v1.ImportRepositoryResponse, error) {
	api := v1.NewImportRepositoryAPIJSONClient(c.baseURL, c.httpClient, c.opts...)
	return api.ImportRepository(ctx, in)
}

// ImportProtectedBranch imports a protected branch for a repository.
func (c *ImportClient) ImportProtectedBranch(ctx context.Context, in *v1.ImportProtectedBranchRequest) (*v1.ImportProtectedBranchResponse, error) {
	api := v1.NewImportProtectedBranchAPIJSONClient(c.baseURL, c.httpClient, c.opts...)
	return api.ImportProtectedBranch(ctx, in)
}

// ImportIssueComment imports a comment for an imported issue.
func (c *ImportClient) ImportIssueComment(ctx context.Context, in *v1.ImportIssueCommentRequest) (*v1.ImportIssueCommentResponse, error) {
	api := v1.NewImportIssueCommentAPIJSONClient(c.baseURL, c.httpClient, c.opts...)
	return api.ImportIssueComment(ctx, in)
}

// ImportTimelineEvent imports time line events
func (c *ImportClient) ImportTimelineEvent(ctx context.Context, in *v1.ImportTimelineEventsRequest) (*v1.ImportTimelineEventsResponse, error) {
	api := v1.NewTimelineEventsAPIJSONClient(c.baseURL, c.httpClient, c.opts...)
	return api.ImportTimelineEvents(ctx, in)
}

// ImportIssue imports an issue for an imported repository.
func (c *ImportClient) ImportIssue(ctx context.Context, in *v1.ImportIssueRequest) (*v1.ImportIssueResponse, error) {
	api := v1.NewImportIssueAPIJSONClient(c.baseURL, c.httpClient, c.opts...)
	return api.ImportIssue(ctx, in)
}

// ImportPullRequest imports an issue for an imported repository.
func (c *ImportClient) ImportPullRequest(ctx context.Context, in *v1.ImportPullRequestRequest) (*v1.ImportPullRequestResponse, error) {
	api := v1.NewImportPullRequestAPIJSONClient(c.baseURL, c.httpClient, c.opts...)
	return api.ImportPullRequest(ctx, in)
}

// ImportPullRequestReview imports a pr review for an imported repository.
func (c *ImportClient) ImportPullRequestReview(ctx context.Context, in *v1.ImportPullRequestReviewRequest) (*v1.ImportPullRequestReviewResponse, error) {
	api := v1.NewImportPullRequestReviewAPIJSONClient(c.baseURL, c.httpClient, c.opts...)
	return api.ImportPullRequestReview(ctx, in)
}

// ImportReactions imports reactions for an imported resource.
func (c *ImportClient) ImportReactions(ctx context.Context, in *v1.ImportReactionsRequest) (*v1.ImportReactionsResponse, error) {
	api := v1.NewImportReactionsAPIJSONClient(c.baseURL, c.httpClient, c.opts...)
	return api.ImportReactions(ctx, in)
}

// ImportMilestones imports milestones for an imported repository.
func (c *ImportClient) ImportMilestones(ctx context.Context, in *v1.ImportMilestonesRequest) (*v1.ImportMilestonesResponse, error) {
	api := v1.NewImportMilestonesAPIJSONClient(c.baseURL, c.httpClient, c.opts...)
	return api.ImportMilestones(ctx, in)
}

// CreateAssetStoragePolicy creates a storage policy required to upload assets.
func (c *ImportClient) CreateAssetStoragePolicy(ctx context.Context, in *v1.CreateAssetStoragePolicyRequest) (*v1.CreateAssetStoragePolicyResponse, error) {
	api := v1.NewImportAssetAPIJSONClient(c.baseURL, c.httpClient, c.opts...)
	return api.CreateAssetStoragePolicy(ctx, in)
}

// ImportLabels imports labels for a repository.
func (c *ImportClient) ImportLabels(ctx context.Context, in *v1.ImportLabelsRequest) (*v1.ImportLabelsResponse, error) {
	api := v1.NewImportLabelsAPIJSONClient(c.baseURL, c.httpClient, c.opts...)
	return api.ImportLabels(ctx, in)
}

// AddLabelsToIssue adds labels to an issue in a repository.
func (c *ImportClient) AddLabelsToIssue(ctx context.Context, in *v1.AddLabelsToIssueRequest) (*v1.AddLabelsToIssueResponse, error) {
	api := v1.NewImportLabelsAPIJSONClient(c.baseURL, c.httpClient, c.opts...)
	return api.AddLabelsToIssue(ctx, in)
}

// ImportRelease imports a release for an imported repository.
func (c *ImportClient) ImportRelease(ctx context.Context, in *v1.ImportReleaseRequest) (*v1.ImportReleaseResponse, error) {
	api := v1.NewImportReleaseAPIJSONClient(c.baseURL, c.httpClient, c.opts...)
	return api.ImportRelease(ctx, in)
}

// ImportProject imports a project.
func (c *ImportClient) ImportProject(ctx context.Context, in *v1.ImportProjectRequest) (*v1.ImportProjectResponse, error) {
	api := v1.NewImportProjectAPIJSONClient(c.baseURL, c.httpClient, c.opts...)
	return api.ImportProject(ctx, in)
}

// ImportCommitComment imports a comment for an imported commit.
func (c *ImportClient) ImportCommitComment(ctx context.Context, in *v1.ImportCommitCommentRequest) (*v1.ImportCommitCommentResponse, error) {
	api := v1.NewImportCommitCommentAPIJSONClient(c.baseURL, c.httpClient, c.opts...)
	return api.ImportCommitComment(ctx, in)
}

// ImportProjectColumn imports a project column.
func (c *ImportClient) ImportProjectColumn(ctx context.Context, in *v1.ImportProjectColumnRequest) (*v1.ImportProjectColumnResponse, error) {
	api := v1.NewImportProjectAPIJSONClient(c.baseURL, c.httpClient, c.opts...)
	return api.ImportProjectColumn(ctx, in)
}

// ImportProjectCards imports project cards.
func (c *ImportClient) ImportProjectCards(ctx context.Context, in *v1.ImportProjectCardsRequest) (*v1.ImportProjectCardsResponse, error) {
	api := v1.NewImportProjectAPIJSONClient(c.baseURL, c.httpClient, c.opts...)
	return api.ImportProjectCards(ctx, in)
}

// ImportCloseIssueReferences imports project cards.
func (c *ImportClient) ImportCloseIssueReferences(ctx context.Context, in *v1.ImportCloseIssueReferencesRequest) (*v1.ImportCloseIssueReferencesResponse, error) {
	api := v1.NewImportCloseIssueReferencesAPIJSONClient(c.baseURL, c.httpClient, c.opts...)
	return api.ImportCloseIssueReferences(ctx, in)
}

// UpdateRepository updates repository settings.
func (c *ImportClient) UpdateRepository(ctx context.Context, in *v1.UpdateRepositoryRequest) (*v1.UpdateRepositoryResponse, error) {
	api := v1.NewImportRepositoryAPIJSONClient(c.baseURL, c.httpClient, c.opts...)
	return api.UpdateRepository(ctx, in)
}

// ImportOrganizationSettings imports organization settings.
func (c *ImportClient) ImportOrganizationSettings(ctx context.Context, in *v1.ImportOrganizationSettingsRequest) (*v1.ImportOrganizationSettingsResponse, error) {
	api := v1.NewImportOrganizationSettingsAPIJSONClient(c.baseURL, c.httpClient, c.opts...)
	return api.ImportOrganizationSettings(ctx, in)
}

// UpdateActionsSettings updates actions settings.
func (c *ImportClient) UpdateActionsSettings(ctx context.Context, in *v1.UpdateActionsSettingsRequest) (*v1.UpdateActionsSettingsResponse, error) {
	api := v1.NewImportRepositoryAPIJSONClient(c.baseURL, c.httpClient, c.opts...)
	return api.UpdateActionsSettings(ctx, in)
}

// EditIssue edits an issue.
func (c *ImportClient) EditIssue(ctx context.Context, in *v1.EditIssueRequest) (*v1.EditIssueResponse, error) {
	api := v1.NewEditIssueAPIJSONClient(c.baseURL, c.httpClient, c.opts...)
	return api.EditIssue(ctx, in)
}

// EditIssueComment edits an issue comment.
func (c *ImportClient) EditIssueComment(ctx context.Context, in *v1.EditIssueCommentRequest) (*v1.EditIssueCommentResponse, error) {
	api := v1.NewEditIssueCommentAPIJSONClient(c.baseURL, c.httpClient, c.opts...)
	return api.EditIssueComment(ctx, in)
}

// EditPullRequest edits a pull request.
func (c *ImportClient) EditPullRequest(ctx context.Context, in *v1.EditPullRequestRequest) (*v1.EditPullRequestResponse, error) {
	api := v1.NewEditPullRequestAPIJSONClient(c.baseURL, c.httpClient, c.opts...)
	return api.EditPullRequest(ctx, in)
}

// EditPullRequestReview edits a pull request review.
func (c *ImportClient) EditPullRequestReview(ctx context.Context, in *v1.EditPullRequestReviewRequest) (*v1.EditPullRequestReviewResponse, error) {
	api := v1.NewEditPullRequestReviewAPIJSONClient(c.baseURL, c.httpClient, c.opts...)
	return api.EditPullRequestReview(ctx, in)
}

// EditPullRequestReviewThread edits a pull request review thread.
func (c *ImportClient) EditPullRequestReviewThread(ctx context.Context, in *v1.EditPullRequestReviewThreadRequest) (*v1.EditPullRequestReviewThreadResponse, error) {
	api := v1.NewEditPullRequestReviewThreadAPIJSONClient(c.baseURL, c.httpClient, c.opts...)
	return api.EditPullRequestReviewThread(ctx, in)
}

// EditPullRequestReviewComment edits a pull request review comment.
func (c *ImportClient) EditPullRequestReviewComment(ctx context.Context, in *v1.EditPullRequestReviewCommentRequest) (*v1.EditPullRequestReviewCommentResponse, error) {
	api := v1.NewEditPullRequestReviewCommentAPIJSONClient(c.baseURL, c.httpClient, c.opts...)
	return api.EditPullRequestReviewComment(ctx, in)
}
