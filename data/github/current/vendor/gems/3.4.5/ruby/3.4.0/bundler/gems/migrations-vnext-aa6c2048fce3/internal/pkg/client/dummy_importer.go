package client

import (
	"context"
	"fmt"
	"hash/crc32"
	"math/rand"
	"sync"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	v1 "github.com/github/migrations-vnext/internal/pkg/octoshift/imports/v1"
	"github.com/spaolacci/murmur3"
)

// DummyImporter is an implementation of the `Importer` interface that is used
// for testing purposes.
type DummyImporter struct {
	Mutex                     sync.Mutex
	Issues                    []*v1.ImportIssueRequest
	Comments                  []*v1.ImportIssueCommentRequest
	TimeLineEvents            []*v1.ImportTimelineEventsRequest
	Reactions                 []*v1.ImportReactionsRequest
	Organizations             []*v1.ImportOrganizationRequest
	Teams                     []*v1.ImportTeamRequest
	Repositories              []*v1.ImportRepositoryRequest
	ProtectedBranches         []*v1.ImportProtectedBranchRequest
	Mannequins                []*v1.CreateMannequinRequest
	Milestones                []*v1.ImportMilestonesRequest
	StoragePolicies           []*v1.CreateAssetStoragePolicyRequest
	RepositoryLabels          []*v1.ImportLabelsRequest
	AddIssueLabels            []*v1.AddLabelsToIssueRequest
	Releases                  []*v1.ImportReleaseRequest
	PullRequests              []*v1.ImportPullRequestRequest
	PullRequestReviews        []*v1.ImportPullRequestReviewRequest
	Projects                  []*v1.ImportProjectRequest
	CommitComments            []*v1.ImportCommitCommentRequest
	ProjectColumns            []*v1.ImportProjectColumnRequest
	ProjectCards              []*v1.ImportProjectCardsRequest
	CloseIssueReferences      []*v1.ImportCloseIssueReferencesRequest
	UpdateRepositoryReqs      []*v1.UpdateRepositoryRequest
	OrganizationSettings      []*v1.ImportOrganizationSettingsRequest
	UpdateActionsSettingsReqs []*v1.UpdateActionsSettingsRequest
	ReleaseAssets             []*v1.CreateAssetStoragePolicyRequest
	Logger                    log.Logger
}

// Make sure that `DummyImporter` implements the `Importer` interface.
var _ Importer = &DummyImporter{}

// NewDummyImporter creates a new `DummyImporter` instance.
func NewDummyImporter(logger log.Logger) *DummyImporter {
	return &DummyImporter{
		Logger: logger,
	}
}

// ImportIssue is a dummy implementation that logs and locally stores the issue.
func (d *DummyImporter) ImportIssue(_ context.Context, in *v1.ImportIssueRequest) (*v1.ImportIssueResponse, error) {
	d.Logger.Info("dummy importer: issue comment",
		kvp.Int64("repo_id", in.RepositoryId),
		kvp.Int64("number", in.Number),
		kvp.String("author_login", in.AuthorLogin),
		kvp.String("body", in.Body),
		kvp.Any("created_at", in.CreatedAt))

	d.Mutex.Lock()
	defer d.Mutex.Unlock()
	d.Issues = append(d.Issues, in)

	return &v1.ImportIssueResponse{Issue: &v1.Issue{Id: 1234}}, nil
}

// ImportIssueComment is a dummy implementation that logs and locally stores the issue comment.
func (d *DummyImporter) ImportIssueComment(_ context.Context, in *v1.ImportIssueCommentRequest) (*v1.ImportIssueCommentResponse, error) {
	d.Logger.Info("dummy importer: issue comment",
		kvp.Int64("issue_id", in.IssueId),
		kvp.String("author_login", in.AuthorLogin),
		kvp.String("body", in.Body),
		kvp.Any("created_at", in.CreatedAt))

	d.Mutex.Lock()
	defer d.Mutex.Unlock()
	d.Comments = append(d.Comments, in)

	return &v1.ImportIssueCommentResponse{IssueComment: &v1.IssueComment{Id: 1234}}, nil
}

// ImportTimelineEvent is a dummy implementation that logs and locally stores the TimelineEvents.
func (d *DummyImporter) ImportTimelineEvent(_ context.Context, in *v1.ImportTimelineEventsRequest) (*v1.ImportTimelineEventsResponse, error) {
	d.Logger.Info("dummy importer: timeline events", kvp.Int("event_count", len(in.TimelineEvents)))

	d.Mutex.Lock()
	defer d.Mutex.Unlock()
	d.TimeLineEvents = append(d.TimeLineEvents, in)

	return &v1.ImportTimelineEventsResponse{}, nil
}

// ImportReactions is a dummy implementation that logs and locally stores the Reactions.
func (d *DummyImporter) ImportReactions(_ context.Context, in *v1.ImportReactionsRequest) (*v1.ImportReactionsResponse, error) {
	d.Logger.Info("dummy importer: Reactions",
		kvp.Int64("subject_id", in.SubjectId),
		kvp.String("subject_type", in.SubjectType.String()),
		kvp.Int("reaction_count", len(in.Reactions)),
	)

	d.Mutex.Lock()
	defer d.Mutex.Unlock()
	d.Reactions = append(d.Reactions, in)

	return &v1.ImportReactionsResponse{
		Reactions: []*v1.Reaction{
			{
				Id: 1234,
			},
		},
	}, nil
}

// CreateMannequin is a dummy implementation that logs and locally stores the mannequin.
func (d *DummyImporter) CreateMannequin(_ context.Context, in *v1.CreateMannequinRequest) (*v1.CreateMannequinResponse, error) {
	d.Logger.Info("dummy importer: mannequin",
		kvp.Int64("owner_id", in.OwnerId),
		kvp.String("profile_name", in.ProfileName),
		kvp.String("source_login", in.SourceLogin),
		kvp.String("email", in.Email),
	)

	hash := murmur3.New32()
	if _, err := hash.Write([]byte(in.SourceLogin)); err != nil {
		return nil, fmt.Errorf("failed to write data to hash: %w", err)
	}

	d.Mutex.Lock()
	defer d.Mutex.Unlock()
	d.Mannequins = append(d.Mannequins, in)

	return &v1.CreateMannequinResponse{Mannequin: &v1.Mannequin{Id: 1, Login: fmt.Sprintf("%x", hash.Sum32())}}, nil
}

// FindMannequin is a dummy implementation that logs and locally stores the found mannequin.
func (d *DummyImporter) FindMannequin(_ context.Context, in *v1.FindMannequinRequest) (*v1.FindMannequinResponse, error) {
	d.Logger.Info("dummy importer: found mannequin",
		kvp.Int64("owner_id", in.OwnerId),
		kvp.String("source_login", in.SourceLogin),
	)

	d.Mutex.Lock()
	defer d.Mutex.Unlock()
	d.Mannequins = append(d.Mannequins, &v1.CreateMannequinRequest{
		OwnerId:     in.OwnerId,
		SourceLogin: in.SourceLogin,
	})

	return &v1.FindMannequinResponse{Mannequin: &v1.Mannequin{Id: 1, Login: in.SourceLogin}}, nil
}

// ImportOrganization is a dummy implementation that logs and locally stores the organization.
func (d *DummyImporter) ImportOrganization(_ context.Context, in *v1.ImportOrganizationRequest) (*v1.ImportOrganizationResponse, error) {
	d.Logger.Info("dummy importer: organization",
		kvp.Int64("target_enterprise_id", in.TargetEnterpriseId),
		kvp.String("target_org_name", in.TargetOrgName),
		kvp.Int64("user_id", in.UserId),
	)

	d.Mutex.Lock()
	defer d.Mutex.Unlock()
	d.Organizations = append(d.Organizations, in)

	return &v1.ImportOrganizationResponse{Id: 1}, nil
}

// ImportTeam is a dummy implementation that logs and locally stores the team.
func (d *DummyImporter) ImportTeam(_ context.Context, in *v1.ImportTeamRequest) (*v1.ImportTeamResponse, error) {
	d.Logger.Info("dummy importer: team",
		kvp.Int64("target_org_id", in.TargetOrgId),
		kvp.String("team_name", in.TeamName),
		kvp.String("team_description", in.TeamDescription.GetValue()),
		kvp.Int64("parent_team_id", in.ParentTeamId.GetValue()),
	)

	d.Mutex.Lock()
	defer d.Mutex.Unlock()
	d.Teams = append(d.Teams, in)

	return &v1.ImportTeamResponse{Id: consistentID(in.TeamName)}, nil
}

// ImportRepository is a dummy implementation that logs and locally stores the repository.
func (d *DummyImporter) ImportRepository(_ context.Context, in *v1.ImportRepositoryRequest) (*v1.ImportRepositoryResponse, error) {
	d.Logger.Info("dummy importer: repository",
		kvp.Int64("owner_id", in.OwnerId),
		kvp.String("name", in.Name),
		kvp.String("visibility", in.Visibility.String()),
	)

	d.Mutex.Lock()
	defer d.Mutex.Unlock()
	d.Repositories = append(d.Repositories, in)

	return &v1.ImportRepositoryResponse{Repository: &v1.Repository{Id: 2, HttpUrl: "http://ghe.dev/acme/widgets"}}, nil
}

// ImportProtectedBranch is a dummy implementation that logs and locally stores the protected branch.
func (d *DummyImporter) ImportProtectedBranch(_ context.Context, in *v1.ImportProtectedBranchRequest) (*v1.ImportProtectedBranchResponse, error) {
	d.Logger.Info("dummy importer: protected_branch",
		kvp.String("name", in.Name),
		kvp.Int64("repo", in.RepositoryId),
	)
	d.Mutex.Lock()
	defer d.Mutex.Unlock()
	d.ProtectedBranches = append(d.ProtectedBranches, in)
	return &v1.ImportProtectedBranchResponse{
		ProtectedBranch: &v1.ProtectedBranch{
			Id: 1234,
		},
	}, nil
}

// ImportMilestones is a dummy implementation that logs and locally stores the milestones.
func (d *DummyImporter) ImportMilestones(_ context.Context, in *v1.ImportMilestonesRequest) (*v1.ImportMilestonesResponse, error) {
	for _, milestone := range in.Milestones {
		d.Logger.Info("dummy importer: milestone",
			kvp.Int64("repository_id", in.RepositoryId),
			kvp.Int64("source_id", milestone.SourceId),
			kvp.String("title", milestone.Title),
			kvp.String("created_by_user_login", milestone.CreatedByUserLogin),
			kvp.String("description", milestone.Description),
			kvp.String("state", milestone.State.String()),
			kvp.Any("due_on", milestone.DueOn),
			kvp.Any("created_at", milestone.CreatedAt),
			kvp.Any("updated_at", milestone.UpdatedAt),
			kvp.Any("closed_at", milestone.ClosedAt),
			kvp.Int64s("issue_ids", milestone.IssueIds),
		)
	}

	d.Mutex.Lock()
	defer d.Mutex.Unlock()
	d.Milestones = append(d.Milestones, in)

	return &v1.ImportMilestonesResponse{
		MilestoneMappings: []*v1.MilestoneMapping{
			{
				Id:       1,
				SourceId: 1,
			},
		},
	}, nil
}

// CreateAssetStoragePolicy is a dummy implementation that logs and locally stores the request.
func (d *DummyImporter) CreateAssetStoragePolicy(_ context.Context, in *v1.CreateAssetStoragePolicyRequest) (*v1.CreateAssetStoragePolicyResponse, error) {
	d.Mutex.Lock()
	defer d.Mutex.Unlock()
	resp := &v1.CreateAssetStoragePolicyResponse{
		UploadUrl:         "",
		Headers:           []*v1.PolicyData{},
		FormData:          []*v1.PolicyData{},
		StoragePolicyType: 0,
		AssetType:         in.AssetType,
		AssetId:           0,
	}
	switch in.AssetType {
	case v1.AssetType_ASSET_TYPE_RELEASE_ASSET:
		resp.AssetUrl = fmt.Sprintf("http://testhub.dev/some-repo/%d/%s", in.ReleaseId, in.Name)
		d.ReleaseAssets = append(d.ReleaseAssets, in)
	default:
		resp.AssetUrl = fmt.Sprintf("http://testhub.dev/user-assets/thisisfake/%s", in.Name)
		d.StoragePolicies = append(d.StoragePolicies, in)
	}

	return resp, nil
}

// ImportLabels imports labels for a repository.
func (d *DummyImporter) ImportLabels(ctx context.Context, in *v1.ImportLabelsRequest) (*v1.ImportLabelsResponse, error) {
	d.Mutex.Lock()
	defer d.Mutex.Unlock()
	d.RepositoryLabels = append(d.RepositoryLabels, in)
	return &v1.ImportLabelsResponse{}, nil
}

// AddLabelsToIssue adds labels to an issue in a repository.
func (d *DummyImporter) AddLabelsToIssue(ctx context.Context, in *v1.AddLabelsToIssueRequest) (*v1.AddLabelsToIssueResponse, error) {
	d.Mutex.Lock()
	defer d.Mutex.Unlock()
	d.AddIssueLabels = append(d.AddIssueLabels, in)
	return &v1.AddLabelsToIssueResponse{}, nil
}

// ImportRelease is a dummy implementation that logs and locally stores the request.
func (d *DummyImporter) ImportRelease(ctx context.Context, in *v1.ImportReleaseRequest) (*v1.ImportReleaseResponse, error) {
	d.Mutex.Lock()
	defer d.Mutex.Unlock()
	d.Releases = append(d.Releases, in)
	return &v1.ImportReleaseResponse{
		Release: &v1.Release{
			Id: 1234,
		},
	}, nil
}

// ImportPullRequest is a dummy implementation that logs and locally stores the request.
func (d *DummyImporter) ImportPullRequest(ctx context.Context, in *v1.ImportPullRequestRequest) (*v1.ImportPullRequestResponse, error) {
	d.Logger.Info("dummy importer: pull request",
		kvp.Int64("repo_id", in.RepositoryId),
		kvp.Int64("number", in.Number),
		kvp.String("author_login", in.AuthorLogin),
		kvp.String("body", in.Body),
		kvp.String("title", in.Title),
		kvp.String("head_ref", in.HeadRefName),
		kvp.String("base_ref", in.BaseRefName),
		kvp.Any("created_at", in.CreatedAt),
		kvp.Any("closed_at", in.ClosedAt),
		kvp.Bool("draft", in.IsDraft),
	)
	d.Mutex.Lock()
	defer d.Mutex.Unlock()
	d.PullRequests = append(d.PullRequests, in)

	return &v1.ImportPullRequestResponse{PullRequest: &v1.PullRequest{Id: 1234, IssueId: 1234}}, nil
}

// ImportPullRequestReview is a dummy implementation that logs and locally stores the request.
func (d *DummyImporter) ImportPullRequestReview(ctx context.Context, in *v1.ImportPullRequestReviewRequest) (*v1.ImportPullRequestReviewResponse, error) {
	d.Logger.Info("dummy importer: pull request review",
		kvp.String("head_sha", in.HeadSha),
		kvp.Any("created_at", in.CreatedAt),
		kvp.Any("submitted_at", in.SubmittedAt),
		kvp.String("state", in.State.String()),
		kvp.Int64("pr id", in.PullRequestId),
	)
	d.Mutex.Lock()
	defer d.Mutex.Unlock()
	d.PullRequestReviews = append(d.PullRequestReviews, in)

	threads := []*v1.PullRequestReviewThreadResponse{}
	for _, t := range in.Threads {
		thread := &v1.PullRequestReviewThreadResponse{
			Id: 1234,
		}
		for range t.Comments {
			thread.ReviewComments = append(thread.ReviewComments, &v1.PullRequestReviewCommentResponse{Id: 1234})
		}
		threads = append(threads, thread)
	}

	comments := []*v1.PullRequestReviewCommentResponse{}
	for range in.Comments {
		comments = append(comments, &v1.PullRequestReviewCommentResponse{
			Id: 1234,
		})
	}

	return &v1.ImportPullRequestReviewResponse{
		PullRequestReview: &v1.PullRequestReview{
			Id:             1234,
			ReviewThreads:  threads,
			ReviewComments: comments,
		},
	}, nil
}

// ImportProject is a dummy implementation that logs and locally stores the project.
func (d *DummyImporter) ImportProject(_ context.Context, in *v1.ImportProjectRequest) (*v1.ImportProjectResponse, error) {
	d.Logger.Info("dummy importer: project",
		kvp.String("name", in.Name),
		kvp.Int64("number", in.Number),
		kvp.String("owner", in.OwnerLogin),
		kvp.String("owner_type", in.OwnerType.String()),
		kvp.String("creator", in.CreatorLogin),
	)

	d.Mutex.Lock()
	defer d.Mutex.Unlock()
	d.Projects = append(d.Projects, in)

	return &v1.ImportProjectResponse{Project: &v1.Project{Id: 1}}, nil
}

// ImportCommitComment is a dummy implementation that logs and locally stores the commit comment.
func (d *DummyImporter) ImportCommitComment(ctx context.Context, request *v1.ImportCommitCommentRequest) (*v1.ImportCommitCommentResponse, error) {
	d.Logger.Info("dummy importer: commit comment",
		kvp.Int64("repo_id", request.RepositoryId),
		kvp.String("author_login", request.AuthorLogin),
		kvp.String("body", request.Body),
		kvp.Any("created_at", request.CreatedAt),
	)

	d.Mutex.Lock()
	defer d.Mutex.Unlock()
	d.CommitComments = append(d.CommitComments, request)

	return &v1.ImportCommitCommentResponse{Id: 1}, nil
}

// ImportProjectColumn is a dummy implementation that logs and locally stores the project column.
func (d *DummyImporter) ImportProjectColumn(_ context.Context, in *v1.ImportProjectColumnRequest) (*v1.ImportProjectColumnResponse, error) {
	d.Logger.Info("dummy importer: project column",
		kvp.Int64("imported_project_id", in.ImportedProjectId),
		kvp.String("name", in.Name),
		kvp.String("purpose", in.Purpose.String()),
	)

	d.ProjectColumns = append(d.ProjectColumns, in)

	return &v1.ImportProjectColumnResponse{ImportedProjectColumnId: consistentID(in.Name)}, nil
}

// ImportProjectCards is a dummy implementation that logs and locally stores the project cards.
func (d *DummyImporter) ImportProjectCards(_ context.Context, in *v1.ImportProjectCardsRequest) (*v1.ImportProjectCardsResponse, error) {
	d.Logger.Info("dummy importer: project cards",
		kvp.Int64("imported_project_column_id", in.ImportedProjectColumnId),
		kvp.Int("card_count", len(in.ProjectCards)),
	)

	d.ProjectCards = append(d.ProjectCards, in)

	return &v1.ImportProjectCardsResponse{}, nil
}

// ImportCloseIssueReferences is a dummy implementation that logs and locally stores the close issue references.
func (d *DummyImporter) ImportCloseIssueReferences(_ context.Context, in *v1.ImportCloseIssueReferencesRequest) (*v1.ImportCloseIssueReferencesResponse, error) {
	d.Logger.Info("dummy_importer: close issue references",
		kvp.Any("refs", in.CloseIssueReferences),
	)

	d.CloseIssueReferences = append(d.CloseIssueReferences, in)
	return &v1.ImportCloseIssueReferencesResponse{}, nil
}

// UpdateRepository is a dummy implementation that logs and locally stores the update repository request.
func (d *DummyImporter) UpdateRepository(ctx context.Context, in *v1.UpdateRepositoryRequest) (*v1.UpdateRepositoryResponse, error) {
	d.Logger.Info("dummy_importer: update repository",
		kvp.Any("req", in),
	)
	d.UpdateRepositoryReqs = append(d.UpdateRepositoryReqs, in)
	return &v1.UpdateRepositoryResponse{
		Repository: &v1.Repository{
			Id: 2,
		},
	}, nil
}

// ImportOrganizationSettings is a dummy implementation that logs and locally stores the import organization settings request.
func (d *DummyImporter) ImportOrganizationSettings(ctx context.Context, in *v1.ImportOrganizationSettingsRequest) (*v1.ImportOrganizationSettingsResponse, error) {
	d.Logger.Info("dummy_importer: import organization settings",
		kvp.Any("req", in),
	)
	d.OrganizationSettings = append(d.OrganizationSettings, in)
	return &v1.ImportOrganizationSettingsResponse{}, nil
}

// UpdateActionsSettings is a dummy implementation that logs and locally stores the update actions settings request.
func (d *DummyImporter) UpdateActionsSettings(ctx context.Context, in *v1.UpdateActionsSettingsRequest) (*v1.UpdateActionsSettingsResponse, error) {
	d.Logger.Info("dummy_importer: update actions settings",
		kvp.Any("req", in),
	)
	d.UpdateActionsSettingsReqs = append(d.UpdateActionsSettingsReqs, in)
	return &v1.UpdateActionsSettingsResponse{}, nil
}

// EditIssue is a dummy implementation that logs and locally stores the edit issue request.
func (d *DummyImporter) EditIssue(_ context.Context, in *v1.EditIssueRequest) (*v1.EditIssueResponse, error) {
	d.Logger.Info("dummy_importer: edit issue",
		kvp.Any("req", in))
	return &v1.EditIssueResponse{}, nil
}

// EditIssueComment is a dummy implementation that logs and locally stores the edit issue comment request.
func (d *DummyImporter) EditIssueComment(_ context.Context, in *v1.EditIssueCommentRequest) (*v1.EditIssueCommentResponse, error) {
	d.Logger.Info("dummy_importer: edit issue comment",
		kvp.Any("req", in))
	return &v1.EditIssueCommentResponse{}, nil
}

// EditPullRequest is a dummy implementation that logs the edit pull request request.
func (d *DummyImporter) EditPullRequest(_ context.Context, in *v1.EditPullRequestRequest) (*v1.EditPullRequestResponse, error) {
	d.Logger.Info("dummy_importer: edit pull request",
		kvp.Any("req", in))
	return &v1.EditPullRequestResponse{}, nil
}

// EditPullRequestReview is a dummy implementation that logs the edit pull request review request.
func (d *DummyImporter) EditPullRequestReview(_ context.Context, in *v1.EditPullRequestReviewRequest) (*v1.EditPullRequestReviewResponse, error) {
	d.Logger.Info("dummy_importer: edit pull request review",
		kvp.Any("req", in))
	return &v1.EditPullRequestReviewResponse{}, nil
}

// EditPullRequestReviewThread is a dummy implementation that logs and locally stores the edit pull request review thread request.
func (d *DummyImporter) EditPullRequestReviewThread(_ context.Context, in *v1.EditPullRequestReviewThreadRequest) (*v1.EditPullRequestReviewThreadResponse, error) {
	d.Logger.Info("dummy_importer: edit pull request review thread",
		kvp.Any("req", in))
	return &v1.EditPullRequestReviewThreadResponse{}, nil
}

// EditPullRequestReviewComment is a dummy implementation that logs the edit pull request review comment request.
func (d *DummyImporter) EditPullRequestReviewComment(_ context.Context, in *v1.EditPullRequestReviewCommentRequest) (*v1.EditPullRequestReviewCommentResponse, error) {
	d.Logger.Info("dummy_importer: edit pull request review comment",
		kvp.Any("req", in))
	return &v1.EditPullRequestReviewCommentResponse{}, nil
}

// consistentID generates a consistent ID for a given seed string.
func consistentID(seedStr string) int64 {
	// Convert the string to a numeric hash (crc32 checksum in this case)
	hash := int64(crc32.ChecksumIEEE([]byte(seedStr)))

	// Seed the random number generator with the hash value
	source := rand.NewSource(hash)

	// Generate a random int64 number (you can also constrain it to a specific range if needed)
	randomInt64 := source.Int63() // Generates a positive int64 value

	// Let's use low number for now to ease debugging as in dev mode collisions are not likely to happen
	return randomInt64 % 1024
}
