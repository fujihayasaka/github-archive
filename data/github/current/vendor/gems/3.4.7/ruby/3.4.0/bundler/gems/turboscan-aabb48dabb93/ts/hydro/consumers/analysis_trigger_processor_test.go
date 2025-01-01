package consumers

import (
	"bytes"
	"context"
	"strings"
	"testing"
	"time"

	"github.com/github/go-http/v2/middleware/requestid"
	"github.com/github/turboscan/ts/gormext"
	"github.com/github/turboscan/ts/mysql/managedanalysis"
	"github.com/github/turboscan/ts/twirp/clients/aqueduct"
	"google.golang.org/protobuf/types/known/timestamppb"
	"google.golang.org/protobuf/types/known/wrapperspb"

	envelope "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	"go.uber.org/mock/gomock"
	"google.golang.org/protobuf/proto"

	"github.com/stretchr/testify/require"

	"github.com/github/turboscan/ts"

	cshydro "github.com/github/hydro-schemas-go/hydro/schemas/code_scanning/v0"
	tshydro "github.com/github/hydro-schemas-go/hydro/schemas/github/v1"
	"github.com/github/hydro-schemas-go/hydro/schemas/github/v1/entities"
	oldtshydro "github.com/github/hydro-schemas-go/hydro/schemas/turboscan/v0"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/github/turboscan/ts/hydro/topics"
	"github.com/github/turboscan/ts/jobs"
	"github.com/github/turboscan/ts/mocks"
)

func createPostReceiveTestMsg() *tshydro.PostReceive {
	return &tshydro.PostReceive{
		Repository: &entities.Repository{
			Id:            1,
			DefaultBranch: "main",
		},
		Owner: &entities.User{Id: 123},
		RefUpdates: []*tshydro.PostReceive_RefUpdate{
			{
				RefName:        "refs/heads/main",
				CurrentRefOid:  "123456",
				PreviousRefOid: "123000",
			},
			{
				RefName:        "refs/heads/feature",
				CurrentRefOid:  "110",
				PreviousRefOid: "100",
			},
			{
				RefName:        "refs/heads/protected",
				CurrentRefOid:  "aaaa",
				PreviousRefOid: "aaaa",
			},
		},
		Actor: &entities.User{
			Login:         "push_user",
			NextGlobalId:  "ngid123",
			GlobalRelayId: "grid123",
		},
		PushedAt: timestamppb.Now(),
	}
}

func createPullRequestSynchronizeTestMessage() *tshydro.PullRequestSynchronize {
	repo := &entities.Repository{
		Id:            1,
		DefaultBranch: "main",
		OwnerId:       wrapperspb.UInt32(123),
	}
	t := timestamppb.Now()
	return &tshydro.PullRequestSynchronize{
		Repository:     repo,
		BaseRepository: repo,
		Actor: &entities.User{
			Login:        "push_user",
			NextGlobalId: "ngid123",
		},
		PullRequest: &entities.PullRequest{
			BaseBranch: []byte("main"),
			HeadSha:    "123456",
			HeadBranch: []byte("foo"),
			Id:         456,
			CreatedAt:  t,
			UpdatedAt:  t,
		},
		Issue: &entities.Issue{
			Number: 123,
		},
		Ref:       []byte("refs/heads/foo"),
		BeforeOid: "123456",
		AfterOid:  "aaaaaa",
	}
}

func createPullRequestCreateTestMessage() *tshydro.PullRequestCreate {
	repo := &entities.Repository{
		Id:            1,
		DefaultBranch: "main",
	}
	return &tshydro.PullRequestCreate{
		RequestContext: &entities.RequestContext{
			RequestId: requestid.NewGitHubRequestID(),
		},
		Repository:     repo,
		HeadRepository: repo,
		Actor: &entities.User{
			Login:        "push_user",
			NextGlobalId: "ngid123",
		},
		PullRequest: &entities.PullRequest{
			Id:         123,
			BaseBranch: []byte("main"),
			HeadSha:    "123456",
			HeadBranch: []byte("foo"),
			CreatedAt:  timestamppb.Now(),
		},
		Issue: &entities.Issue{
			Number: 123,
		},
		RepositoryOwner: &entities.User{Id: 123},
	}
}

// setRepoEnabled mocks the onboarding status of a repository as `ENABLED` in the processor
func setRepoEnabled(t *testing.T, p *AnalysisTriggerProcessor, repoID ts.RepositoryEID) {
	t.Helper()
	p.repos.enabled[repoID] = struct{}{}
	require.True(t, p.repos.Contains(repoID))
}

type hydroPublisherMock struct {
	arg []*cshydro.ManagedAnalysesExpectedCodeqlRun
}

// ExpectedCodeqlRunEvent implements ExpectedCodeqlRunPublisher.
func (h *hydroPublisherMock) ExpectedCodeqlRunEvent(ctx context.Context, arg *cshydro.ManagedAnalysesExpectedCodeqlRun) error {
	h.arg = append(h.arg, arg)
	return nil
}

// CodeqlRunEvent implements CodeqlRunPublisher.
func (h *hydroPublisherMock) CodeqlRunEvent(_ context.Context, m *oldtshydro.CodeqlRun) error {
	return nil
}

func (h *hydroPublisherMock) Reset() {
	h.arg = nil
}

var _ ExpectedCodeqlRunPublisher = (*hydroPublisherMock)(nil)

func requirePostReceivePublishedMessage(t *testing.T, msg *tshydro.PostReceive, refUpdates *tshydro.PostReceive_RefUpdate, hydroPublisher *hydroPublisherMock) {
	t.Helper()
	for _, arg := range hydroPublisher.arg {
		if bytes.Equal(arg.Ref, []byte(refUpdates.RefName)) {
			require.Equal(t, int64(msg.Repository.Id), arg.RepositoryId)
			require.Equal(t, int64(msg.Owner.GetId()), arg.OwnerId)
			require.Equal(t, msg.PushedAt.AsTime(), arg.TriggeringEventTime.AsTime())
			require.Equal(t, "post_receive", arg.TriggeringEventType)
			require.Equal(t, []byte(refUpdates.RefName), arg.Ref)
			require.Equal(t, refUpdates.CurrentRefOid, arg.CommitOid)
			require.Equal(t, strings.TrimPrefix(refUpdates.RefName, "refs/heads/") == msg.Repository.DefaultBranch, arg.DefaultBranch)
			return
		}
	}
	require.Fail(t, "expected message not found")
}

func TestPostReceiveProcessor_Success(t *testing.T) {
	mockCtrl := gomock.NewController(t)
	codeQLRequirementMock := mocks.NewMockCodeQLRequirement(mockCtrl)
	hydroPublisher := &hydroPublisherMock{}
	aqueductMock := &aqueduct.AqueductMock{}
	p := NewAnalysisTriggerProcessor(hydroPublisher, nil, aqueductMock, codeQLRequirementMock, true)
	msg := createPostReceiveTestMsg()
	expectedRepoID := ts.RepositoryEID(msg.Repository.Id)
	setRepoEnabled(t, p, expectedRepoID)

	codeQLRequirementMock.EXPECT().IsCodeQLRequired(gomock.Any(), expectedRepoID, ts.Ref("refs/heads/feature")).Return(false, nil).Times(1)
	codeQLRequirementMock.EXPECT().IsCodeQLRequired(gomock.Any(), expectedRepoID, ts.Ref("refs/heads/protected")).Return(false, nil).Times(1)

	requireProcessEnvelope(t, p, msg, topics.PostReceive)

	require.Len(t, aqueductMock.EnqueuedJobs(), 1)
	job := jobs.RunCodeqlOnPush{
		RepoID:          expectedRepoID,
		OwnerID:         ts.OwnerEID(123),
		Ref:             []byte("refs/heads/main"),
		Sha:             "123456",
		ActorLogin:      "push_user",
		ActorGRID:       "ngid123",
		InDefaultBranch: true,
		EventTimeStamp:  gormext.ConvertPBTime(msg.PushedAt),
	}

	requirePostReceivePublishedMessage(t, msg, msg.RefUpdates[0], hydroPublisher)
	require.Equal(t, job, aqueductMock.EnqueuedJobs()[0])
}

func TestPostReceiveProcessor_CodeQLRequired(t *testing.T) {
	mockCtrl := gomock.NewController(t)
	codeQLRequirementMock := mocks.NewMockCodeQLRequirement(mockCtrl)
	hydroPublisher := &hydroPublisherMock{}
	aqueductMock := &aqueduct.AqueductMock{}
	p := NewAnalysisTriggerProcessor(hydroPublisher, nil, aqueductMock, codeQLRequirementMock, true)

	msg := createPostReceiveTestMsg()
	expectedRepoID := ts.RepositoryEID(msg.Repository.Id)
	setRepoEnabled(t, p, expectedRepoID)
	msg.RefUpdates[0].RefName = "refs/heads/develop"

	codeQLRequirementMock.EXPECT().IsCodeQLRequired(gomock.Any(), expectedRepoID, ts.Ref("refs/heads/feature")).Return(true, nil).Times(1)
	codeQLRequirementMock.EXPECT().IsCodeQLRequired(gomock.Any(), expectedRepoID, ts.Ref("refs/heads/protected")).Return(false, nil).Times(1)
	codeQLRequirementMock.EXPECT().IsCodeQLRequired(gomock.Any(), expectedRepoID, ts.Ref("refs/heads/develop")).Return(false, nil).Times(1)

	requireProcessEnvelope(t, p, msg, topics.PostReceive)

	require.Len(t, aqueductMock.EnqueuedJobs(), 1)
	job := jobs.RunCodeqlOnPush{
		RepoID:          expectedRepoID,
		OwnerID:         ts.OwnerEID(123),
		Ref:             []byte("refs/heads/feature"),
		Sha:             "110",
		ActorLogin:      "push_user",
		ActorGRID:       "ngid123",
		InDefaultBranch: false,
		EventTimeStamp:  gormext.ConvertPBTime(msg.PushedAt),
	}

	requirePostReceivePublishedMessage(t, msg, msg.RefUpdates[1], hydroPublisher)
	require.Equal(t, job, aqueductMock.EnqueuedJobs()[0])
}

func TestPostReceiveProcessor_RepoIsNotEnabled(t *testing.T) {
	aqueductMock := &aqueduct.AqueductMock{}
	p := NewAnalysisTriggerProcessor(nil, nil, aqueductMock, nil, true)

	require.False(t, p.repos.Contains(1))

	requireProcessEnvelope(t, p, createPostReceiveTestMsg(), topics.PostReceive)
	require.Len(t, aqueductMock.EnqueuedJobs(), 0)
}

func TestPostReceiveProcessor_NotDefaultBranch(t *testing.T) {
	mockCtrl := gomock.NewController(t)
	codeQLRequirementMock := mocks.NewMockCodeQLRequirement(mockCtrl)
	aqueductMock := &aqueduct.AqueductMock{}
	p := NewAnalysisTriggerProcessor(nil, nil, aqueductMock, codeQLRequirementMock, true)

	msg := createPostReceiveTestMsg()
	expectedRepoID := ts.RepositoryEID(msg.Repository.Id)
	setRepoEnabled(t, p, expectedRepoID)
	msg.RefUpdates[0].RefName = "refs/heads/develop"

	codeQLRequirementMock.EXPECT().IsCodeQLRequired(gomock.Any(), expectedRepoID, ts.Ref("refs/heads/develop")).Return(false, nil).Times(1)
	codeQLRequirementMock.EXPECT().IsCodeQLRequired(gomock.Any(), expectedRepoID, ts.Ref("refs/heads/feature")).Return(false, nil).Times(1)
	codeQLRequirementMock.EXPECT().IsCodeQLRequired(gomock.Any(), expectedRepoID, ts.Ref("refs/heads/protected")).Return(false, nil).Times(1)

	requireProcessEnvelope(t, p, msg, topics.PostReceive)

	require.Len(t, aqueductMock.EnqueuedJobs(), 0)
}

func TestPostReceiveProcessor_ProtectedBranches(t *testing.T) {
	ctx := context.Background()
	mockCtrl := gomock.NewController(t)
	codeQLRequirementMock := mocks.NewMockCodeQLRequirement(mockCtrl)
	hydroPublisher := &hydroPublisherMock{}
	aqueductMock := &aqueduct.AqueductMock{}
	p := NewAnalysisTriggerProcessor(hydroPublisher, nil, aqueductMock, codeQLRequirementMock, true)

	msg := createPostReceiveTestMsg()
	expectedRepoID := ts.RepositoryEID(msg.Repository.Id)
	setRepoEnabled(t, p, expectedRepoID)
	protoMsg, err := proto.Marshal(msg)
	require.NoError(t, err)

	codeQLRequirementMock.EXPECT().IsCodeQLRequired(gomock.Any(), expectedRepoID, ts.Ref("refs/heads/feature")).Return(false, nil).Times(1)
	codeQLRequirementMock.EXPECT().IsCodeQLRequired(gomock.Any(), expectedRepoID, ts.Ref("refs/heads/protected")).Return(false, nil).Times(1)
	require.NoError(t, p.ProcessEnvelope(ctx, &envelope.Envelope{Message: protoMsg}, topics.PostReceive))

	// Only the default branch job should be enqueued
	require.Len(t, aqueductMock.EnqueuedJobs(), 1)
	requirePostReceivePublishedMessage(t, msg, msg.RefUpdates[0], hydroPublisher)

	aqueductMock.Reset()
	hydroPublisher.Reset()

	codeQLRequirementMock.EXPECT().IsCodeQLRequired(gomock.Any(), expectedRepoID, ts.Ref("refs/heads/feature")).Return(false, nil).Times(1)
	codeQLRequirementMock.EXPECT().IsCodeQLRequired(gomock.Any(), expectedRepoID, ts.Ref("refs/heads/protected")).Return(true, nil).Times(1)

	require.NoError(t, p.ProcessEnvelope(ctx, &envelope.Envelope{Message: protoMsg}, topics.PostReceive))
	// Two jobs are enqueued (one for the default branch and one for the protected branch)
	require.Len(t, aqueductMock.EnqueuedJobs(), 2)
	requirePostReceivePublishedMessage(t, msg, msg.RefUpdates[0], hydroPublisher)
	requirePostReceivePublishedMessage(t, msg, msg.RefUpdates[2], hydroPublisher)

	aqueductMock.Reset()
	hydroPublisher.Reset()

	codeQLRequirementMock.EXPECT().IsCodeQLRequired(gomock.Any(), expectedRepoID, ts.Ref("refs/heads/feature")).Return(true, nil).Times(1)
	codeQLRequirementMock.EXPECT().IsCodeQLRequired(gomock.Any(), expectedRepoID, ts.Ref("refs/heads/protected")).Return(true, nil).Times(1)

	require.NoError(t, p.ProcessEnvelope(ctx, &envelope.Envelope{Message: protoMsg}, topics.PostReceive))
	require.Len(t, aqueductMock.EnqueuedJobs(), 3)
	requirePostReceivePublishedMessage(t, msg, msg.RefUpdates[0], hydroPublisher)
	requirePostReceivePublishedMessage(t, msg, msg.RefUpdates[1], hydroPublisher)
	requirePostReceivePublishedMessage(t, msg, msg.RefUpdates[2], hydroPublisher)
}

func TestPostReceiveProcessor_MissingActor(t *testing.T) {
	aqueductMock := &aqueduct.AqueductMock{}
	p := NewAnalysisTriggerProcessor(nil, nil, aqueductMock, nil, true)
	msg := createPostReceiveTestMsg()
	setRepoEnabled(t, p, ts.RepositoryEID(msg.Repository.Id))
	msg.Actor = nil
	requireProcessEnvelope(t, p, msg, topics.PostReceive)

	require.Len(t, aqueductMock.EnqueuedJobs(), 0)
}

func TestPollEnabledRepos(t *testing.T) {
	ctx := context.Background()
	db := dbtest.RequireConnectionWithoutAutoIncrement(t)
	ma := managedanalysis.NewService(db, &hydroPublisherMock{})

	p := NewAnalysisTriggerProcessor(nil, ma, nil, nil, true)

	require.Empty(t, p.repos.enabled)

	configs := []*ts.CodeqlConfig{
		(&ts.CodeqlConfig{RepositoryID: 1, Languages: ts.Languages{"javascript"}}).MakeCurrent(),
		(&ts.CodeqlConfig{RepositoryID: 2, Languages: ts.Languages{"javascript"}}).MakeStaged(),
		(&ts.CodeqlConfig{RepositoryID: 3, Languages: ts.Languages{"javascript"}}).Deprecate(),
		(&ts.CodeqlConfig{RepositoryID: 4, Languages: ts.Languages{"python", "java"}}).MakeCurrent(),
	}

	for _, config := range configs {
		dbtest.RequireCreate(t, db, config)
	}

	deadlineCtx, cancel := context.WithDeadline(ctx, time.Now().Add(100*time.Millisecond))
	defer cancel()
	err := p.PollEnabledRepos(deadlineCtx, 50*time.Millisecond)
	require.NoError(t, err)
	require.Equal(t, 3, len(p.repos.enabled))
}

func TestRefreshRepos(t *testing.T) {
	ctx := context.Background()
	db := dbtest.RequireConnectionWithoutAutoIncrement(t)
	ma := managedanalysis.NewService(db, &hydroPublisherMock{})

	p := NewAnalysisTriggerProcessor(nil, ma, nil, nil, true)

	require.Empty(t, p.repos.enabled)

	config := (&ts.CodeqlConfig{
		RepositoryID: 1,
		Languages:    ts.Languages{"javascript"},
	}).MakeCurrent()
	dbtest.RequireCreate(t, db, config)

	err := p.repos.FullRefresh(ctx)
	require.NoError(t, err)
	require.Len(t, p.repos.enabled, 1)

	// Add a new config
	config = (&ts.CodeqlConfig{
		RepositoryID: 2,
		Languages:    ts.Languages{"javascript"},
	}).MakeCurrent()
	dbtest.RequireCreate(t, db, config)

	err = p.repos.IncrementalRefresh(ctx)
	require.NoError(t, err)
	require.Len(t, p.repos.enabled, 2)
}

func TestPullRequestSynchronize_Success(t *testing.T) {
	aqueductMock := &aqueduct.AqueductMock{}
	hydroPublisher := &hydroPublisherMock{}
	p := NewAnalysisTriggerProcessor(hydroPublisher, nil, aqueductMock, nil, true)

	msg := createPullRequestSynchronizeTestMessage()
	expectedRepoID := ts.RepositoryEID(msg.Repository.Id)

	setRepoEnabled(t, p, expectedRepoID)
	requireProcessEnvelope(t, p, msg, topics.PullRequestSynchronize)

	require.Equal(t, int64(msg.Repository.Id), hydroPublisher.arg[0].RepositoryId)
	require.Equal(t, int64(msg.Repository.GetOwnerId().GetValue()), hydroPublisher.arg[0].OwnerId)
	require.Equal(t, msg.PullRequest.UpdatedAt.AsTime(), hydroPublisher.arg[0].TriggeringEventTime.AsTime())
	require.Equal(t, "pull_request_synchronize", hydroPublisher.arg[0].TriggeringEventType)
	require.Equal(t, []byte("refs/pull/123/head"), hydroPublisher.arg[0].Ref)
	require.Equal(t, msg.GetBeforeOid(), hydroPublisher.arg[0].CommitOid)
	require.Equal(t, string(msg.PullRequest.BaseBranch) == msg.Repository.DefaultBranch, hydroPublisher.arg[0].DefaultBranch)

	eventTimeStamp := gormext.ConvertPBTime(msg.PullRequest.UpdatedAt)
	job := jobs.RunCodeqlOnPullRequest{
		RepoID:         expectedRepoID,
		OwnerID:        ts.OwnerEID(123),
		Sha:            "123456",
		ActorLogin:     "push_user",
		ActorGRID:      "ngid123",
		PRNumber:       123,
		EventTimestamp: eventTimeStamp,
	}
	require.Equal(t, job, aqueductMock.EnqueuedJobs()[0])
}

func TestPullRequestSynchronize_RepoIsNotEnabled(t *testing.T) {
	aqueductMock := &aqueduct.AqueductMock{}
	p := NewAnalysisTriggerProcessor(nil, nil, aqueductMock, nil, true)

	require.False(t, p.repos.Contains(1))

	requireProcessEnvelope(t, p, createPullRequestSynchronizeTestMessage(), topics.PullRequestSynchronize)
	require.Len(t, aqueductMock.EnqueuedJobs(), 0)
}

func TestPullRequestSynchronize_IgnoredEvents(t *testing.T) {
	aqueductMock := &aqueduct.AqueductMock{}
	mockCtrl := gomock.NewController(t)
	codeQLRequirementMock := mocks.NewMockCodeQLRequirement(mockCtrl)
	p := NewAnalysisTriggerProcessor(nil, nil, aqueductMock, codeQLRequirementMock, true)

	msg := createPullRequestSynchronizeTestMessage()
	expectedRepoID := ts.RepositoryEID(msg.Repository.Id)
	setRepoEnabled(t, p, expectedRepoID)
	codeQLRequirementMock.EXPECT().IsCodeQLRequired(gomock.Any(), expectedRepoID, ts.Ref("refs/heads/not-main")).Return(false, nil).Times(1)

	// Check that we ignore the event when the target branch is not the repository default branch
	msg.PullRequest.BaseBranch = []byte("not-main")
	requireProcessEnvelope(t, p, msg, topics.PullRequestSynchronize)
	require.Len(t, aqueductMock.EnqueuedJobs(), 0)

	// Check that we ignore the event when the PR is on a fork
	msg = createPullRequestSynchronizeTestMessage()
	msg.BaseRepository = &entities.Repository{
		Id:            2,
		DefaultBranch: "main",
	}
	requireProcessEnvelope(t, p, msg, topics.PullRequestSynchronize)
	require.Len(t, aqueductMock.EnqueuedJobs(), 0)

	// Check that we ignore the event when the actor is missing
	msg = createPullRequestSynchronizeTestMessage()
	msg.Actor = nil
	requireProcessEnvelope(t, p, msg, topics.PullRequestSynchronize)
	require.Len(t, aqueductMock.EnqueuedJobs(), 0)
}

func TestPullRequestSynchronize_DependabotEvents(t *testing.T) {
	aqueductMock := &aqueduct.AqueductMock{}
	p := NewAnalysisTriggerProcessor(nil, nil, aqueductMock, nil, true)
	msg := createPullRequestSynchronizeTestMessage()
	setRepoEnabled(t, p, ts.RepositoryEID(msg.Repository.Id))
	msg.Actor.Login = "dependabot[bot]"
	requireProcessEnvelope(t, p, msg, topics.PullRequestSynchronize)
	require.Len(t, aqueductMock.EnqueuedJobs(), 1)
	job := jobs.SkipDependabot{
		RepoID:        ts.RepositoryEID(1),
		PullRequestID: msg.PullRequest.Id,
	}
	require.Equal(t, job, aqueductMock.EnqueuedJobs()[0])
}

func TestPullRequestSynchronize_CodeQLRequired(t *testing.T) {
	aqueductMock := &aqueduct.AqueductMock{}
	mockCtrl := gomock.NewController(t)
	codeQLRequirementMock := mocks.NewMockCodeQLRequirement(mockCtrl)
	hydroPublisher := &hydroPublisherMock{}
	p := NewAnalysisTriggerProcessor(hydroPublisher, nil, aqueductMock, codeQLRequirementMock, true)

	msg := createPullRequestSynchronizeTestMessage()
	expectedRepoID := ts.RepositoryEID(msg.Repository.Id)
	setRepoEnabled(t, p, expectedRepoID)

	msg.PullRequest.BaseBranch = []byte("protected")

	codeQLRequirementMock.EXPECT().IsCodeQLRequired(gomock.Any(), expectedRepoID, ts.Ref("refs/heads/protected")).Return(true, nil).Times(1)
	requireProcessEnvelope(t, p, msg, topics.PullRequestSynchronize)

	require.Equal(t, int64(msg.Repository.Id), hydroPublisher.arg[0].RepositoryId)
	require.Equal(t, int64(msg.Repository.GetOwnerId().GetValue()), hydroPublisher.arg[0].OwnerId)
	require.Equal(t, msg.PullRequest.CreatedAt.AsTime(), hydroPublisher.arg[0].TriggeringEventTime.AsTime())
	require.Equal(t, "pull_request_synchronize", hydroPublisher.arg[0].TriggeringEventType)
	require.Equal(t, []byte("refs/pull/123/head"), hydroPublisher.arg[0].Ref)
	require.Equal(t, msg.GetBeforeOid(), hydroPublisher.arg[0].CommitOid)
	require.Equal(t, string(msg.PullRequest.BaseBranch) == msg.Repository.DefaultBranch, hydroPublisher.arg[0].DefaultBranch)

	require.Len(t, aqueductMock.EnqueuedJobs(), 1)
}

func TestPullRequestCreate_Success(t *testing.T) {
	aqueductMock := &aqueduct.AqueductMock{}
	hydroPublisher := &hydroPublisherMock{}
	p := NewAnalysisTriggerProcessor(hydroPublisher, nil, aqueductMock, nil, true)

	msg := createPullRequestCreateTestMessage()
	setRepoEnabled(t, p, ts.RepositoryEID(msg.Repository.Id))
	requireProcessEnvelope(t, p, msg, topics.PullRequestCreate)

	require.Equal(t, int64(msg.Repository.Id), hydroPublisher.arg[0].RepositoryId)
	require.Equal(t, int64(msg.RepositoryOwner.GetId()), hydroPublisher.arg[0].OwnerId)
	require.Equal(t, msg.PullRequest.CreatedAt.AsTime(), hydroPublisher.arg[0].TriggeringEventTime.AsTime())
	require.Equal(t, "pull_request_create", hydroPublisher.arg[0].TriggeringEventType)
	require.Equal(t, msg.PullRequest.GetHeadSha(), hydroPublisher.arg[0].CommitOid)

	require.Len(t, aqueductMock.EnqueuedJobs(), 1)
	job := jobs.RunCodeqlOnPullRequest{
		RepoID:         ts.RepositoryEID(1),
		OwnerID:        ts.OwnerEID(123),
		Sha:            "123456",
		ActorLogin:     "push_user",
		ActorGRID:      "ngid123",
		PRNumber:       123,
		EventTimestamp: gormext.ConvertPBTime(msg.PullRequest.CreatedAt),
	}
	require.Equal(t, job, aqueductMock.EnqueuedJobs()[0])
}

func TestPullRequestCreate_RepoIsNotEnabled(t *testing.T) {
	aqueductMock := &aqueduct.AqueductMock{}
	hydroPublisher := &hydroPublisherMock{}
	p := NewAnalysisTriggerProcessor(hydroPublisher, nil, aqueductMock, nil, true)
	require.False(t, p.repos.Contains(1))

	requireProcessEnvelope(t, p, createPullRequestCreateTestMessage(), topics.PullRequestCreate)
	require.Len(t, aqueductMock.EnqueuedJobs(), 0)
	require.Len(t, hydroPublisher.arg, 0)
}

func TestPullRequestCreate_IgnoredEvents(t *testing.T) {
	mockCtrl := gomock.NewController(t)
	codeQLRequirementMock := mocks.NewMockCodeQLRequirement(mockCtrl)
	aqueductMock := &aqueduct.AqueductMock{}
	hydroPublisher := &hydroPublisherMock{}
	p := NewAnalysisTriggerProcessor(hydroPublisher, nil, aqueductMock, codeQLRequirementMock, true)

	msg := createPullRequestCreateTestMessage()
	expectedRepoID := ts.RepositoryEID(msg.Repository.Id)
	setRepoEnabled(t, p, expectedRepoID)

	// Check that we ignore the event when the target branch is not the repository default branch
	msg.PullRequest.BaseBranch = []byte("not-main")

	codeQLRequirementMock.EXPECT().IsCodeQLRequired(gomock.Any(), expectedRepoID, ts.Ref("refs/heads/not-main")).Return(false, nil).Times(1)

	requireProcessEnvelope(t, p, msg, topics.PullRequestCreate)
	require.Len(t, aqueductMock.EnqueuedJobs(), 0)
	require.Len(t, hydroPublisher.arg, 0)

	// Check that we ignore the event when the PR is on a fork
	msg = createPullRequestCreateTestMessage()
	msg.HeadRepository = &entities.Repository{
		Id:            2,
		DefaultBranch: "main",
	}
	requireProcessEnvelope(t, p, msg, topics.PullRequestCreate)
	require.Len(t, aqueductMock.EnqueuedJobs(), 0)
	require.Len(t, hydroPublisher.arg, 0)

	// Check that we ignore the event when actor is missing
	msg = createPullRequestCreateTestMessage()
	msg.Actor = nil
	requireProcessEnvelope(t, p, msg, topics.PullRequestCreate)
	require.Len(t, aqueductMock.EnqueuedJobs(), 0)
	require.Len(t, hydroPublisher.arg, 0)
}

func TestPullRequestCreate_CodeQLRequired(t *testing.T) {
	mockCtrl := gomock.NewController(t)
	codeQLRequirementMock := mocks.NewMockCodeQLRequirement(mockCtrl)
	hydroPublisher := &hydroPublisherMock{}
	aqueductMock := &aqueduct.AqueductMock{}
	p := NewAnalysisTriggerProcessor(hydroPublisher, nil, aqueductMock, codeQLRequirementMock, true)

	msg := createPullRequestCreateTestMessage()
	expectedRepoID := ts.RepositoryEID(msg.Repository.Id)
	setRepoEnabled(t, p, expectedRepoID)

	msg.PullRequest.BaseBranch = []byte("protected-1")

	codeQLRequirementMock.EXPECT().IsCodeQLRequired(gomock.Any(), expectedRepoID, ts.Ref("refs/heads/protected-1")).Return(false, nil).Times(1)

	requireProcessEnvelope(t, p, msg, topics.PullRequestCreate)
	require.Len(t, aqueductMock.EnqueuedJobs(), 0)
	require.Len(t, hydroPublisher.arg, 0)

	aqueductMock.Reset()
	hydroPublisher.Reset()

	codeQLRequirementMock.EXPECT().IsCodeQLRequired(gomock.Any(), expectedRepoID, ts.Ref("refs/heads/protected-1")).Return(true, nil).Times(1)

	requireProcessEnvelope(t, p, msg, topics.PullRequestCreate)
	require.Len(t, aqueductMock.EnqueuedJobs(), 1)

	require.Equal(t, int64(msg.Repository.Id), hydroPublisher.arg[0].RepositoryId)
	require.Equal(t, int64(msg.RepositoryOwner.GetId()), hydroPublisher.arg[0].OwnerId)
	require.Equal(t, msg.PullRequest.CreatedAt.AsTime(), hydroPublisher.arg[0].TriggeringEventTime.AsTime())
	require.Equal(t, "pull_request_create", hydroPublisher.arg[0].TriggeringEventType)
	require.Equal(t, msg.PullRequest.GetHeadSha(), hydroPublisher.arg[0].CommitOid)

}

func TestPostReceiveProcessor_ActorGRID(t *testing.T) {
	mockCtrl := gomock.NewController(t)
	aqueductMock := &aqueduct.AqueductMock{}
	codeQLRequirementMock := mocks.NewMockCodeQLRequirement(mockCtrl)
	hydroPublisher := mocks.NewMockExpectedCodeqlRunPublisher(mockCtrl)
	useNextGlobalID := false
	p := NewAnalysisTriggerProcessor(hydroPublisher, nil, aqueductMock, codeQLRequirementMock, useNextGlobalID)
	msg := createPostReceiveTestMsg()
	expectedRepoID := ts.RepositoryEID(msg.Repository.Id)
	setRepoEnabled(t, p, expectedRepoID)

	codeQLRequirementMock.EXPECT().IsCodeQLRequired(gomock.Any(), expectedRepoID, ts.Ref("refs/heads/feature")).Return(false, nil).Times(1)
	codeQLRequirementMock.EXPECT().IsCodeQLRequired(gomock.Any(), expectedRepoID, ts.Ref("refs/heads/protected")).Return(false, nil).Times(1)
	hydroPublisher.EXPECT().ExpectedCodeqlRunEvent(gomock.Any(), gomock.Any())

	requireProcessEnvelope(t, p, msg, topics.PostReceive)

	require.Len(t, aqueductMock.EnqueuedJobs(), 1)
	job := jobs.RunCodeqlOnPush{
		RepoID:          expectedRepoID,
		OwnerID:         ts.OwnerEID(123),
		Ref:             []byte("refs/heads/main"),
		Sha:             "123456",
		ActorLogin:      "push_user",
		ActorGRID:       "grid123", // <- this is the important bit
		InDefaultBranch: true,
		EventTimeStamp:  gormext.ConvertPBTime(msg.PushedAt),
	}
	require.Equal(t, job, aqueductMock.EnqueuedJobs()[0])
}
