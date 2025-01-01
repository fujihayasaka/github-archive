package processor_test

import (
	"context"
	"testing"
	"time"

	"github.com/github/go-http/v2/middleware/requestid"

	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	githubv1 "github.com/github/hydro-schemas-go/hydro/schemas/github/v1"
	entitiesv1 "github.com/github/hydro-schemas-go/hydro/schemas/github/v1/entities"
	"github.com/github/spokes-proto/gen/go/v1/commits"
	"github.com/github/turboghas/internal/dbtest"
	"github.com/github/turboghas/internal/mocks"
	twirpTurboghas "github.com/github/turboghas/internal/monolith_twirp/turboghas/v1"
	v1 "github.com/github/turboghas/internal/monolith_twirp/turboghas/v1"
	"github.com/github/turboghas/internal/processor"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/encoding/protojson"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/reflect/protoreflect"
	"google.golang.org/protobuf/types/known/timestamppb"
	"google.golang.org/protobuf/types/known/wrapperspb"
)

type mockApi struct {
	mock.Mock
}

// this is so that gopls can help us generate the missing mock methods.
var _ v1.TurboghasAPI = &mockApi{}

// GetEntities implements v1.TurboghasAPI.
func (m *mockApi) GetEntities(ctx context.Context, request *v1.GetEntitiesRequest) (*v1.GetEntitiesResponse, error) {
	args := m.Called(ctx, request)
	return args.Get(0).(*twirpTurboghas.GetEntitiesResponse), args.Error(1)
}

// GetRepositories implements v1.TurboghasAPI.
func (m *mockApi) GetRepositories(ctx context.Context, request *v1.GetRepositoriesRequest) (*v1.GetRepositoriesResponse, error) {
	args := m.Called(ctx, request)
	return args.Get(0).(*twirpTurboghas.GetRepositoriesResponse), args.Error(1)
}

// GetUsers implements v1.TurboghasAPI.
func (m *mockApi) GetUsers(ctx context.Context, request *v1.GetUsersRequest) (*v1.GetUsersResponse, error) {
	args := m.Called(ctx, request)
	return args.Get(0).(*twirpTurboghas.GetUsersResponse), args.Error(1)
}

func (m *mockApi) FindUsersByEmails(ctx context.Context, request *twirpTurboghas.FindUsersByEmailsRequest) (*twirpTurboghas.FindUsersByEmailsResponse, error) {
	args := m.Called(ctx, request)
	return args.Get(0).(*twirpTurboghas.FindUsersByEmailsResponse), args.Error(1)
}

func (m *mockApi) GetBillableUsers(ctx context.Context, request *twirpTurboghas.GetBillableUsersRequest) (*twirpTurboghas.GetBillableUsersResponse, error) {
	args := m.Called(ctx, request)
	return args.Get(0).(*twirpTurboghas.GetBillableUsersResponse), args.Error(1)
}

type mockPublisher struct {
	mock.Mock
}

func (m *mockPublisher) Publish(msg protoreflect.ProtoMessage, opts ...hydro.PublishOption) error {
	args := m.Called(msg, opts)
	return args.Error(0)
}

func TestTopics(t *testing.T) {
	require.NotEmpty(t, processor.Topics())
}

func TestInvalidTopic(t *testing.T) {
	db := dbtest.RequireConnection(t)
	d := dbtest.Data(db)
	ctx := t.Context()

	require.Error(t, processor.New(d, &mockApi{}, &mockPublisher{}, nil, &mockDeps{}).ProcessMessage(ctx, &githubv1.CommitHovercardHover{}))
}

func TestInvalidJob(t *testing.T) {
	db := dbtest.RequireConnection(t)
	d := dbtest.Data(db)
	ctx := t.Context()

	require.Error(t, processor.New(d, &mockApi{}, &mockPublisher{}, nil, &mockDeps{}).ProcessJob(ctx, &aqueduct.Job{Queue: "invalid"}))
}

func TestQueueDepthCache(t *testing.T) {
	ctx := t.Context()
	t.Run("ttl-250", func(t *testing.T) {
		queue := mocks.Cleanup(t, &mockAqueduct{})
		queue.On("QueueDepth", mocks.IsContext, "turboghas", "turboghas_1").Return(int64(10), nil).Once()
		queue.On("QueueDepth", mocks.IsContext, "turboghas", "turboghas_2").Return(int64(20), nil).Once()

		q := processor.NewQueueDepthCache(queue, 250*time.Millisecond)
		{
			count, err := q.QueueDepth(ctx, "turboghas", "turboghas_1")
			require.Equal(t, int64(10), count)
			require.NoError(t, err)
		}
		{
			count, err := q.QueueDepth(ctx, "turboghas", "turboghas_1")
			require.Equal(t, int64(10), count)
			require.NoError(t, err)
		}
		{
			count, err := q.QueueDepth(ctx, "turboghas", "turboghas_2")
			require.Equal(t, int64(20), count)
			require.NoError(t, err)
		}
	})
	t.Run("ttl-zero", func(t *testing.T) {
		queue := mocks.Cleanup(t, &mockAqueduct{})
		queue.On("QueueDepth", mocks.IsContext, "turboghas", "turboghas_1").Return(int64(10), nil).Times(2)
		queue.On("QueueDepth", mocks.IsContext, "turboghas", "turboghas_2").Return(int64(20), nil).Once()

		q := processor.NewQueueDepthCache(queue, 0)
		{
			count, err := q.QueueDepth(ctx, "turboghas", "turboghas_1")
			require.Equal(t, int64(10), count)
			require.NoError(t, err)
		}
		{
			count, err := q.QueueDepth(ctx, "turboghas", "turboghas_1")
			require.Equal(t, int64(10), count)
			require.NoError(t, err)
		}
		{
			count, err := q.QueueDepth(ctx, "turboghas", "turboghas_2")
			require.Equal(t, int64(20), count)
			require.NoError(t, err)
		}
	})
}

func TestUnwrapHydro(t *testing.T) {
	testMessage := &githubv1.RepositoryInvite{
		Actor: &entitiesv1.User{
			Login: "ghost",
		},
		Repository: &entitiesv1.Repository{
			Id:      1,
			OwnerId: &wrapperspb.UInt32Value{Value: 101},
		},
	}

	value, err := hydro.NewDefaultEncoder().Encode(testMessage, time.Now())
	require.NoError(t, err)

	var called bool

	require.NoError(t, processor.UnwrapMessage(processor.UnwrapEnvelope(func(ctx context.Context, inner proto.Message) error {
		msg, ok := inner.(*githubv1.RepositoryInvite)
		require.True(t, ok)
		require.Equal(t, uint32(1), msg.Repository.Id)
		called = true
		return nil
	}))(t.Context(), hydro.Message{
		Value: value,
	}))

	require.True(t, called)
}

func TestProcessJobJSON(t *testing.T) {
	db := dbtest.RequireConnection(t)
	d := dbtest.Data(db)
	ctx := t.Context()

	deps := mocks.Cleanup(t, &mockDeps{})
	deps.On("GetEmailsFromRefUpdates", mocks.IsContext, uint64(1), []*githubv1.PostReceive_RefUpdate{
		{RefName: "refs/heads/main", PreviousRefOid: "4d39ee7d0836ac8c17a662685db03a85fa845a4f", CurrentRefOid: "3161860805acb9e11eadfddb6e92274ba00158ac"},
	}).Return([]*commits.Contributor{}, nil).Once()

	msg, err := protojson.Marshal(&githubv1.PostReceive{
		PushedAt: timestamppb.Now(),
		Actor: &entitiesv1.User{
			Login: "ghost",
		},
		Business: &githubv1.PostReceive_Business{},
		Repository: &entitiesv1.Repository{
			Id:         1,
			Visibility: entitiesv1.Repository_PUBLIC,
		},
		Owner: &entitiesv1.User{
			Id:    1,
			Login: "monalisa",
			Type:  entitiesv1.User_ORGANIZATION,
		},
		RefUpdates: []*githubv1.PostReceive_RefUpdate{
			{RefName: "refs/heads/main", PreviousRefOid: "4d39ee7d0836ac8c17a662685db03a85fa845a4f", CurrentRefOid: "3161860805acb9e11eadfddb6e92274ba00158ac"},
		},
	})
	require.NoError(t, err)

	h := processor.JobHeaders(ctx, &githubv1.PostReceive{})
	h["Content-Type"] = "application/json"

	require.NoError(t, processor.New(d, &mockApi{}, &mockPublisher{}, nil, deps).ProcessJob(ctx, &aqueduct.Job{
		Queue:   processor.PostReceiveQueue,
		Headers: h,
		Payload: msg,
	}))
}

func TestWithRequestContext(t *testing.T) {
	ctx := processor.WithRequestID(t.Context(), &githubv1.PostReceive{
		RequestContext: &entitiesv1.RequestContext{
			RequestId: "test",
		},
	})
	require.Equal(t, requestid.GetGitHubRequestID(ctx), "test")
}

func TestProcessJobProto(t *testing.T) {
	db := dbtest.RequireConnection(t)
	d := dbtest.Data(db)
	ctx := t.Context()

	deps := mocks.Cleanup(t, &mockDeps{})
	deps.On("GetEmailsFromRefUpdates", mocks.IsContext, uint64(1), []*githubv1.PostReceive_RefUpdate{
		{RefName: "refs/heads/main", PreviousRefOid: "4d39ee7d0836ac8c17a662685db03a85fa845a4f", CurrentRefOid: "3161860805acb9e11eadfddb6e92274ba00158ac"},
	}).Return([]*commits.Contributor{}, nil).Once()

	msg, err := proto.Marshal(&githubv1.PostReceive{
		PushedAt: timestamppb.Now(),
		Actor: &entitiesv1.User{
			Login: "ghost",
		},
		Business: &githubv1.PostReceive_Business{},
		Repository: &entitiesv1.Repository{
			Id:         1,
			Visibility: entitiesv1.Repository_PUBLIC,
		},
		Owner: &entitiesv1.User{
			Id:    1,
			Login: "monalisa",
			Type:  entitiesv1.User_ORGANIZATION,
		},
		RefUpdates: []*githubv1.PostReceive_RefUpdate{
			{RefName: "refs/heads/main", PreviousRefOid: "4d39ee7d0836ac8c17a662685db03a85fa845a4f", CurrentRefOid: "3161860805acb9e11eadfddb6e92274ba00158ac"},
		},
	})
	require.NoError(t, err)

	require.NoError(t, processor.New(d, &mockApi{}, &mockPublisher{}, nil, deps).ProcessJob(ctx, &aqueduct.Job{
		Queue:   processor.PostReceiveQueue,
		Payload: msg,
		Headers: processor.JobHeaders(ctx, &githubv1.PostReceive{}),
	}))
}
