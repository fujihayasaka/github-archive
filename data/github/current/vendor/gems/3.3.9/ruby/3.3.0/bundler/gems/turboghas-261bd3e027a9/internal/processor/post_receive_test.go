package processor_test

import (
	"bytes"
	"context"
	"strings"
	"testing"
	"unicode/utf8"

	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	githubv1 "github.com/github/hydro-schemas-go/hydro/schemas/github/v1"
	entitiesv1 "github.com/github/hydro-schemas-go/hydro/schemas/github/v1/entities"
	turboghasv0 "github.com/github/hydro-schemas-go/hydro/schemas/turboghas/v0"
	"github.com/github/spokes-proto/gen/go/v1/commits"
	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/github/turboghas/internal/dbtest"
	"github.com/github/turboghas/internal/fromctx"
	"github.com/github/turboghas/internal/mocks"
	twirpTurboghas "github.com/github/turboghas/internal/monolith_twirp/turboghas/v1"
	"github.com/github/turboghas/internal/processor"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/timestamppb"
)

type mockAqueduct struct {
	mock.Mock
}

func (m *mockAqueduct) Send(ctx context.Context, j aqueduct.Job, opts ...aqueduct.SendOption) (string, error) {
	args := m.Called(ctx, j, opts)
	return args.String(0), args.Error(1)
}

func (m *mockAqueduct) QueueDepth(ctx context.Context, app, queue string) (int64, error) {
	args := m.Called(ctx, app, queue)
	return args.Get(0).(int64), args.Error(1)
}

func TestEmailKey(t *testing.T) {
	require.Equal(t, "", processor.EmailKey([]byte("")))
	require.Equal(t, "user", processor.EmailKey([]byte("User")))
	require.Equal(t, "@test", processor.EmailKey([]byte("@test")))
	require.Equal(t, "test@", processor.EmailKey([]byte("test@")))
	require.Equal(t, "test@test.com", processor.EmailKey([]byte("test@test.com")))
	require.Equal(t, "test@test.com", processor.EmailKey([]byte("test+code@test.com")))
	require.Equal(t, "test+code-1@test.com", processor.EmailKey([]byte("test+code-1+code-2@test.com")))
	require.Equal(t, "test@test.com", processor.EmailKey([]byte("TEST@test.com")))
	require.Equal(t, "user@domain-1", processor.EmailKey([]byte("user@domain-1@domain-2")))
	require.Equal(t, "user@domain-1", processor.EmailKey([]byte("user@domain-1@domain-2 ")))
	require.Equal(t, "user@domain-1", processor.EmailKey([]byte("user@domain-1@")))
	require.Equal(t, `i@domain-1`, processor.EmailKey([]byte("ï@domain-1")))
}

func FuzzEmailKey(f *testing.F) {
	db := dbtest.RequireConnection(f)
	{
		_, err := db.Exec("CREATE TEMPORARY TABLE test_email_key (`email` varchar(255) DEFAULT NULL) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3")
		require.NoError(f, err)
	}
	testcases := []string{"ï@domain-1", "TEST@test.com"}
	for _, tc := range testcases {
		f.Add(tc)
	}
	f.Fuzz(func(t *testing.T, orig string) {
		if !utf8.ValidString(orig) {
			t.Skipf("%q not a valid utf8 string", orig)
			return
		}
		if strings.Count(orig, "@") > 1 || strings.Count(orig, "+") > 0 {
			t.Skipf("%q triggers sanization", orig)
			return
		}
		for _, r := range orig {
			if r > 0xFFFF {
				t.Skipf("%q outside of valid range", orig)
				return
			}
		}
		key := processor.EmailKey([]byte(orig))
		_, err := db.Exec("INSERT INTO test_email_key (email) VALUES (?)", orig)
		require.NoError(t, err)
		var found bool
		require.NoErrorf(t, db.QueryRow("SELECT 1 FROM test_email_key WHERE email = ?", key).Scan(&found), "%q not found by %q", orig, key)
		require.True(t, found)
	})
}

func TestIsBillable(t *testing.T) {
	ctx := fromctx.Env.With(context.Background(), "production")

	require.False(t, processor.IsBillable(ctx, &githubv1.PostReceive{
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
	}))
	require.False(t, processor.IsBillable(ctx, &githubv1.PostReceive{
		PushedAt: timestamppb.Now(),
		Actor: &entitiesv1.User{
			Login: "ghost",
		},
		Business: &githubv1.PostReceive_Business{},
		Repository: &entitiesv1.Repository{
			Id:         1,
			Visibility: entitiesv1.Repository_PRIVATE,
		},
		Owner: &entitiesv1.User{
			Id:    1,
			Login: "monalisa",
			Type:  entitiesv1.User_USER,
		},
		RefUpdates: []*githubv1.PostReceive_RefUpdate{
			{RefName: "refs/heads/main", PreviousRefOid: "4d39ee7d0836ac8c17a662685db03a85fa845a4f", CurrentRefOid: "3161860805acb9e11eadfddb6e92274ba00158ac"},
		},
	}))
	require.False(t, processor.IsBillable(ctx, &githubv1.PostReceive{
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
			Id:                  1,
			Login:               "monalisa",
			Type:                entitiesv1.User_USER,
			IsEnterpriseManaged: true,
		},
		RefUpdates: []*githubv1.PostReceive_RefUpdate{
			{RefName: "refs/heads/main", PreviousRefOid: "4d39ee7d0836ac8c17a662685db03a85fa845a4f", CurrentRefOid: "3161860805acb9e11eadfddb6e92274ba00158ac"},
		},
	}))
	require.False(t, processor.IsBillable(ctx, &githubv1.PostReceive{
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
			Type:  entitiesv1.User_USER,
		},
		RefUpdates: []*githubv1.PostReceive_RefUpdate{
			{RefName: "refs/heads/main", PreviousRefOid: "4d39ee7d0836ac8c17a662685db03a85fa845a4f", CurrentRefOid: "3161860805acb9e11eadfddb6e92274ba00158ac"},
		},
	}))
}

func ProtoEqual(other proto.Message) any {
	return mock.MatchedBy(func(v proto.Message) bool {
		return proto.Equal(other, v)
	})
}

func TestEnterprisePostReceive(t *testing.T) {
	db := dbtest.RequireConnection(t)
	d := dbtest.Data(db)
	ctx := fromctx.Env.With(context.Background(), "enterprise")

	now := timestamppb.Now()

	api := mocks.Cleanup(t, &mockApi{})
	api.On("FindUsersByEmails", mocks.IsContext, ProtoEqual(&twirpTurboghas.FindUsersByEmailsRequest{PushedAt: now, RepositoryId: 1, Emails: [][]byte{[]byte("user@example.com")}})).Return(&twirpTurboghas.FindUsersByEmailsResponse{
		Users: []*twirpTurboghas.FindUsersByEmailsResponse_User{
			{Email: []byte("USER@example.com"), Id: 1, Login: "user"},
		},
	}, nil).Once()
	api.On("GetRepositories", mocks.IsContext, &twirpTurboghas.GetRepositoriesRequest{RepositoryIds: []uint64{1}}).Return(&twirpTurboghas.GetRepositoriesResponse{
		Repositories: map[uint64]*twirpTurboghas.GetRepositoriesResponse_Repository{
			1: {
				Entity: &twirpTurboghas.GetRepositoriesResponse_Entity{
					Id:   1,
					Type: twirpTurboghas.EntityType_ENTITY_TYPE_BUSINESS,
				},
				AdvancedSecurityEnabled: true,
				IsPublic:                true,
				Name:                    "test",
				OwnerId:                 1,
				Owner: &twirpTurboghas.GetUsersResponse_User{
					Login:               "test",
					Type:                twirpTurboghas.UserType_USER_TYPE_ORGANIZATION,
					IsEnterpriseManaged: false,
				},
			},
		},
	}, nil).Once()

	deps := mocks.Cleanup(t, &mockDeps{})
	deps.On("GetEmailsFromRefUpdates", mocks.IsContext, uint64(1), []*githubv1.PostReceive_RefUpdate{
		{RefName: "refs/heads/main", PreviousRefOid: "4d39ee7d0836ac8c17a662685db03a85fa845a4f", CurrentRefOid: "3161860805acb9e11eadfddb6e92274ba00158ac"},
	}).Return([]*commits.Contributor{{EmailBytes: []byte("user@example.com"), CommitOid: &types.ObjectID{Id: "4d39ee7d0836ac8c17a662685db03a85fa845a4f"}}}, nil).Once()

	msg := &githubv1.PostReceive{
		PushedAt: now,
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
	}

	pub := mocks.Cleanup(t, &mockPublisher{})
	pub.On("Publish", mock.MatchedBy(func(billableContribution *turboghasv0.BillableContribution) bool {
		return len(billableContribution.Committers) == 1 && bytes.Equal(billableContribution.Committers[0].Email, []byte("USER@example.com")) && billableContribution.Committers[0].CommitOid == "4d39ee7d0836ac8c17a662685db03a85fa845a4f"
	}), mock.MatchedBy(mocks.Is[[]hydro.PublishOption])).Return(nil).Once()

	queue := mocks.Cleanup(t, &mockAqueduct{})
	queue.On("QueueDepth", mocks.IsContext, "turboghas", "turboghas_PostReceive").Return(int64(0), nil)

	p := processor.New(d, api, pub, queue, deps)

	queue.On("Send", mocks.IsContext, mock.MatchedBy(mocks.Is[aqueduct.Job]), mock.Anything).Run(func(args mock.Arguments) {
		ctx, ok := args.Get(0).(context.Context)
		require.True(t, ok)
		job, ok := args.Get(1).(aqueduct.Job)
		require.True(t, ok)
		require.NoError(t, p.ProcessJob(ctx, &job))
	}).Return("test-job", nil)

	require.NoError(t, p.ProcessMessage(ctx, msg))
}

func TestPostReceive(t *testing.T) {
	db := dbtest.RequireConnection(t)
	d := dbtest.Data(db)
	ctx := context.Background()

	now := timestamppb.Now()

	api := mocks.Cleanup(t, &mockApi{})
	api.On("FindUsersByEmails", mocks.IsContext, ProtoEqual(&twirpTurboghas.FindUsersByEmailsRequest{PushedAt: now, RepositoryId: 1, Emails: [][]byte{[]byte("user@example.com")}})).Return(&twirpTurboghas.FindUsersByEmailsResponse{
		Users: []*twirpTurboghas.FindUsersByEmailsResponse_User{
			{Email: []byte("user-1@example.com"), Id: 1, Login: "user"},
		},
	}, nil).Once()
	api.On("GetRepositories", mocks.IsContext, &twirpTurboghas.GetRepositoriesRequest{RepositoryIds: []uint64{1}}).Return(&twirpTurboghas.GetRepositoriesResponse{
		Repositories: map[uint64]*twirpTurboghas.GetRepositoriesResponse_Repository{
			1: {
				Entity: &twirpTurboghas.GetRepositoriesResponse_Entity{
					Id:   1,
					Type: twirpTurboghas.EntityType_ENTITY_TYPE_BUSINESS,
				},
				AdvancedSecurityEnabled: true,
				Name:                    "test",
				OwnerId:                 1,
				Owner: &twirpTurboghas.GetUsersResponse_User{
					Login:               "test",
					Type:                twirpTurboghas.UserType_USER_TYPE_ORGANIZATION,
					IsEnterpriseManaged: false,
				},
			},
		},
	}, nil).Once()

	deps := mocks.Cleanup(t, &mockDeps{})
	deps.On("GetEmailsFromRefUpdates", mocks.IsContext, uint64(1), []*githubv1.PostReceive_RefUpdate{
		{RefName: "refs/heads/main", PreviousRefOid: "4d39ee7d0836ac8c17a662685db03a85fa845a4f", CurrentRefOid: "3161860805acb9e11eadfddb6e92274ba00158ac"},
	}).Return([]*commits.Contributor{
		{EmailBytes: []byte("user@example.com"), CommitOid: &types.ObjectID{Id: "4d39ee7d0836ac8c17a662685db03a85fa845a4f"}},
	}, nil).Once()

	msg := &githubv1.PostReceive{
		PushedAt: now,
		Actor: &entitiesv1.User{
			Login: "ghost",
		},
		Business: &githubv1.PostReceive_Business{},
		Repository: &entitiesv1.Repository{
			Id:         1,
			Visibility: entitiesv1.Repository_PRIVATE,
		},
		Owner: &entitiesv1.User{
			Id:    1,
			Login: "monalisa",
			Type:  entitiesv1.User_ORGANIZATION,
		},
		RefUpdates: []*githubv1.PostReceive_RefUpdate{
			{RefName: "refs/heads/main", PreviousRefOid: "4d39ee7d0836ac8c17a662685db03a85fa845a4f", CurrentRefOid: "3161860805acb9e11eadfddb6e92274ba00158ac"},
		},
	}

	pub := mocks.Cleanup(t, &mockPublisher{})
	pub.On("Publish", mock.MatchedBy(func(billableContribution *turboghasv0.BillableContribution) bool {
		return len(billableContribution.Committers) == 1
	}), mock.MatchedBy(mocks.Is[[]hydro.PublishOption])).Return(nil).Once()

	queue := mocks.Cleanup(t, &mockAqueduct{})
	queue.On("QueueDepth", mocks.IsContext, "turboghas", "turboghas_PostReceive").Return(int64(0), nil)

	p := processor.New(d, api, pub, queue, deps)

	queue.On("Send", mocks.IsContext, mock.MatchedBy(mocks.Is[aqueduct.Job]), mock.Anything).Run(func(args mock.Arguments) {
		ctx, ok := args.Get(0).(context.Context)
		require.True(t, ok)
		job, ok := args.Get(1).(aqueduct.Job)
		require.True(t, ok)
		require.NoError(t, p.ProcessJob(ctx, &job))
	}).Return("test-job", nil)

	require.NoError(t, p.ProcessMessage(ctx, msg))
}

func TestLargePostReceivePublish(t *testing.T) {
	db := dbtest.RequireConnection(t)
	d := dbtest.Data(db)
	ctx := context.Background()

	now := timestamppb.Now()

	api := mocks.Cleanup(t, &mockApi{})
	deps := mocks.Cleanup(t, &mockDeps{})

	msg := &githubv1.PostReceive{
		PushedAt: now,
		Actor: &entitiesv1.User{
			Login: "ghost",
		},
		Business: &githubv1.PostReceive_Business{},
		Repository: &entitiesv1.Repository{
			Id:         1,
			Visibility: entitiesv1.Repository_PRIVATE,
		},
		Owner: &entitiesv1.User{
			Id:    1,
			Login: "monalisa",
			Type:  entitiesv1.User_ORGANIZATION,
		},
		RefUpdates: make([]*githubv1.PostReceive_RefUpdate, 0, 1000),
	}

	for range 1000 {
		msg.RefUpdates = append(msg.RefUpdates, &githubv1.PostReceive_RefUpdate{
			RefName: "refs/heads/main", PreviousRefOid: "4d39ee7d0836ac8c17a662685db03a85fa845a4f", CurrentRefOid: "3161860805acb9e11eadfddb6e92274ba00158ac",
		})
	}

	pub := mocks.Cleanup(t, &mockPublisher{})
	pub.On("Publish", mock.MatchedBy(mocks.Is[*githubv1.PostReceive]), mock.MatchedBy(mocks.Is[[]hydro.PublishOption])).Return(nil).Once()

	queue := mocks.Cleanup(t, &mockAqueduct{})

	p := processor.New(d, api, pub, queue, deps)

	require.NoError(t, p.ProcessMessage(ctx, msg))
}

func TestLargePostReceiveProcess(t *testing.T) {
	db := dbtest.RequireConnection(t)
	d := dbtest.Data(db)
	ctx := processor.Hydro.With(context.Background(), &processor.HydroContext{Topic: processor.LargePostReceiveTopic})

	now := timestamppb.Now()

	api := mocks.Cleanup(t, &mockApi{})
	api.On("FindUsersByEmails", mocks.IsContext, ProtoEqual(&twirpTurboghas.FindUsersByEmailsRequest{PushedAt: now, RepositoryId: 1, Emails: [][]byte{[]byte("user@example.com")}})).Return(&twirpTurboghas.FindUsersByEmailsResponse{
		Users: []*twirpTurboghas.FindUsersByEmailsResponse_User{
			{Email: []byte("user-1@example.com"), Id: 1, Login: "user"},
		},
	}, nil).Once()
	api.On("GetRepositories", mocks.IsContext, &twirpTurboghas.GetRepositoriesRequest{RepositoryIds: []uint64{1}}).Return(&twirpTurboghas.GetRepositoriesResponse{
		Repositories: map[uint64]*twirpTurboghas.GetRepositoriesResponse_Repository{
			1: {
				Entity: &twirpTurboghas.GetRepositoriesResponse_Entity{
					Id:   1,
					Type: twirpTurboghas.EntityType_ENTITY_TYPE_BUSINESS,
				},
				AdvancedSecurityEnabled: true,
				Name:                    "test",
				OwnerId:                 1,
				Owner: &twirpTurboghas.GetUsersResponse_User{
					Login:               "test",
					Type:                twirpTurboghas.UserType_USER_TYPE_ORGANIZATION,
					IsEnterpriseManaged: false,
				},
			},
		},
	}, nil).Once()

	deps := mocks.Cleanup(t, &mockDeps{})
	deps.On("GetEmailsFromRefUpdates", mocks.IsContext, uint64(1), mock.MatchedBy(mocks.Is[[]*githubv1.PostReceive_RefUpdate])).Return([]*commits.Contributor{
		{EmailBytes: []byte("user@example.com"), CommitOid: &types.ObjectID{Id: "4d39ee7d0836ac8c17a662685db03a85fa845a4f"}},
	}, nil).Once()

	msg := &githubv1.PostReceive{
		PushedAt: now,
		Actor: &entitiesv1.User{
			Login: "ghost",
		},
		Business: &githubv1.PostReceive_Business{},
		Repository: &entitiesv1.Repository{
			Id:         1,
			Visibility: entitiesv1.Repository_PRIVATE,
		},
		Owner: &entitiesv1.User{
			Id:    1,
			Login: "monalisa",
			Type:  entitiesv1.User_ORGANIZATION,
		},
		RefUpdates: make([]*githubv1.PostReceive_RefUpdate, 0, 1000),
	}

	for range 1000 {
		msg.RefUpdates = append(msg.RefUpdates, &githubv1.PostReceive_RefUpdate{
			RefName: "refs/heads/main", PreviousRefOid: "4d39ee7d0836ac8c17a662685db03a85fa845a4f", CurrentRefOid: "3161860805acb9e11eadfddb6e92274ba00158ac",
		})
	}

	pub := mocks.Cleanup(t, &mockPublisher{})
	pub.On("Publish", mock.MatchedBy(func(billableContribution *turboghasv0.BillableContribution) bool {
		return len(billableContribution.Committers) == 1
	}), mock.MatchedBy(mocks.Is[[]hydro.PublishOption])).Return(nil).Once()

	queue := mocks.Cleanup(t, &mockAqueduct{})

	p := processor.New(d, api, pub, queue, deps)

	require.NoError(t, p.ProcessMessage(ctx, msg))
}

func TestPostReceiveTwirpError(t *testing.T) {
	db := dbtest.RequireConnection(t)
	d := dbtest.Data(db)
	ctx := context.Background()

	now := timestamppb.Now()

	api := mocks.Cleanup(t, &mockApi{})
	api.On("FindUsersByEmails", mocks.IsContext, ProtoEqual(&twirpTurboghas.FindUsersByEmailsRequest{PushedAt: now, RepositoryId: 1, Emails: [][]byte{[]byte("user@example.com")}})).Return(&twirpTurboghas.FindUsersByEmailsResponse{
		Users: []*twirpTurboghas.FindUsersByEmailsResponse_User{
			{Email: []byte("user@example.com"), Id: 1, Login: "user"},
		},
	}, nil).Once()
	api.On("GetRepositories", mocks.IsContext, &twirpTurboghas.GetRepositoriesRequest{RepositoryIds: []uint64{1}}).Return(&twirpTurboghas.GetRepositoriesResponse{
		Repositories: map[uint64]*twirpTurboghas.GetRepositoriesResponse_Repository{
			1: {
				Entity: &twirpTurboghas.GetRepositoriesResponse_Entity{
					Id:   1,
					Type: twirpTurboghas.EntityType_ENTITY_TYPE_BUSINESS,
				},
				AdvancedSecurityEnabled: true,
				Name:                    "test",
				OwnerId:                 1,
				Owner: &twirpTurboghas.GetUsersResponse_User{
					Login:               "test",
					Type:                twirpTurboghas.UserType_USER_TYPE_ORGANIZATION,
					IsEnterpriseManaged: false,
				},
			},
		},
	}, nil).Once()

	deps := mocks.Cleanup(t, &mockDeps{})
	deps.On("GetEmailsFromRefUpdates", mocks.IsContext, uint64(1), []*githubv1.PostReceive_RefUpdate{
		{RefName: "refs/heads/main", PreviousRefOid: "4d39ee7d0836ac8c17a662685db03a85fa845a4f", CurrentRefOid: "3161860805acb9e11eadfddb6e92274ba00158ac"},
	}).Return([]*commits.Contributor{
		{EmailBytes: []byte("user@example.com"), CommitOid: &types.ObjectID{Id: "4d39ee7d0836ac8c17a662685db03a85fa845a4f"}},
	}, nil).Once()

	msg := &githubv1.PostReceive{
		PushedAt: now,
		Actor: &entitiesv1.User{
			Login: "ghost",
		},
		Business: &githubv1.PostReceive_Business{},
		Repository: &entitiesv1.Repository{
			Id:         1,
			Visibility: entitiesv1.Repository_PRIVATE,
		},
		Owner: &entitiesv1.User{
			Id:    1,
			Login: "monalisa",
			Type:  entitiesv1.User_ORGANIZATION,
		},
		RefUpdates: []*githubv1.PostReceive_RefUpdate{
			{RefName: "refs/heads/main", PreviousRefOid: "4d39ee7d0836ac8c17a662685db03a85fa845a4f", CurrentRefOid: "3161860805acb9e11eadfddb6e92274ba00158ac"},
		},
	}

	queue := mocks.Cleanup(t, &mockAqueduct{})

	pub := mocks.Cleanup(t, &mockPublisher{})
	pub.On("Publish", mock.MatchedBy(func(billableContribution *turboghasv0.BillableContribution) bool {
		return len(billableContribution.Committers) == 1
	}), mock.MatchedBy(mocks.Is[[]hydro.PublishOption])).Return(nil).Once()

	p := processor.New(d, api, pub, queue, deps)

	queue.On("Send", mocks.IsContext, mock.MatchedBy(mocks.Is[aqueduct.Job]), mock.Anything).Return("", twirp.InvalidArgumentError("message", "too large"))
	queue.On("QueueDepth", mocks.IsContext, "turboghas", "turboghas_PostReceive").Return(int64(0), nil)

	require.NoError(t, p.ProcessMessage(ctx, msg))
}

func TestPostReceiveNoAqueductOrPublisher(t *testing.T) {
	db := dbtest.RequireConnection(t)
	d := dbtest.Data(db)
	ctx := context.Background()

	now := timestamppb.Now()

	api := mocks.Cleanup(t, &mockApi{})
	api.On("FindUsersByEmails", mocks.IsContext, ProtoEqual(&twirpTurboghas.FindUsersByEmailsRequest{PushedAt: now, RepositoryId: 1, Emails: [][]byte{[]byte("user@example.com")}})).Return(&twirpTurboghas.FindUsersByEmailsResponse{
		Users: []*twirpTurboghas.FindUsersByEmailsResponse_User{
			{Email: []byte("user@example.com"), Id: 1, Login: "user"},
		},
	}, nil).Once()
	api.On("GetRepositories", mocks.IsContext, &twirpTurboghas.GetRepositoriesRequest{RepositoryIds: []uint64{1}}).Return(&twirpTurboghas.GetRepositoriesResponse{
		Repositories: map[uint64]*twirpTurboghas.GetRepositoriesResponse_Repository{
			1: {
				Entity: &twirpTurboghas.GetRepositoriesResponse_Entity{
					Id:   1,
					Type: twirpTurboghas.EntityType_ENTITY_TYPE_BUSINESS,
				},
				AdvancedSecurityEnabled: true,
				Name:                    "test",
				OwnerId:                 1,
				Owner: &twirpTurboghas.GetUsersResponse_User{
					Login:               "test",
					Type:                twirpTurboghas.UserType_USER_TYPE_ORGANIZATION,
					IsEnterpriseManaged: false,
				},
			},
		},
	}, nil).Once()
	api.On("GetBillableUsers", mocks.IsContext, &twirpTurboghas.GetBillableUsersRequest{OwnerId: 1}).Return(&twirpTurboghas.GetBillableUsersResponse{
		BillableEntityId:   1,
		BillableEntityType: twirpTurboghas.EntityType_ENTITY_TYPE_BUSINESS,
		UserIds:            []uint64{1},
	}, nil).Once()

	deps := mocks.Cleanup(t, &mockDeps{})
	deps.On("GetEmailsFromRefUpdates", mocks.IsContext, uint64(1), []*githubv1.PostReceive_RefUpdate{
		{RefName: "refs/heads/main", PreviousRefOid: "4d39ee7d0836ac8c17a662685db03a85fa845a4f", CurrentRefOid: "3161860805acb9e11eadfddb6e92274ba00158ac"},
	}).Return([]*commits.Contributor{
		{EmailBytes: []byte("user@example.com"), CommitOid: &types.ObjectID{Id: "4d39ee7d0836ac8c17a662685db03a85fa845a4f"}},
	}, nil).Once()

	msg := &githubv1.PostReceive{
		PushedAt: now,
		Actor: &entitiesv1.User{
			Login: "ghost",
		},
		Business: &githubv1.PostReceive_Business{},
		Repository: &entitiesv1.Repository{
			Id:         1,
			Visibility: entitiesv1.Repository_PRIVATE,
		},
		Owner: &entitiesv1.User{
			Id:    1,
			Login: "monalisa",
			Type:  entitiesv1.User_ORGANIZATION,
		},
		RefUpdates: []*githubv1.PostReceive_RefUpdate{
			{RefName: "refs/heads/main", PreviousRefOid: "4d39ee7d0836ac8c17a662685db03a85fa845a4f", CurrentRefOid: "3161860805acb9e11eadfddb6e92274ba00158ac"},
		},
	}

	p := processor.New(d, api, nil, nil, deps)

	require.NoError(t, p.ProcessMessage(ctx, msg))
}

func TestPostReceiveForDeletedRepository(t *testing.T) {
	db := dbtest.RequireConnection(t)
	d := dbtest.Data(db)
	ctx := context.Background()

	now := timestamppb.Now()

	api := mocks.Cleanup(t, &mockApi{})
	api.On("GetRepositories", mocks.IsContext, &twirpTurboghas.GetRepositoriesRequest{RepositoryIds: []uint64{1}}).Return((*twirpTurboghas.GetRepositoriesResponse)(nil), nil).Once()
	api.On("FindUsersByEmails", mocks.IsContext, ProtoEqual(&twirpTurboghas.FindUsersByEmailsRequest{PushedAt: now, RepositoryId: 1, Emails: [][]byte{[]byte("user@example.com")}})).Return(&twirpTurboghas.FindUsersByEmailsResponse{
		Users: []*twirpTurboghas.FindUsersByEmailsResponse_User{
			{Email: []byte("user@example.com"), Id: 1, Login: "user"},
		},
	}, nil).Once()
	api.On("GetBillableUsers", mocks.IsContext, &twirpTurboghas.GetBillableUsersRequest{OwnerId: 1}).Return(&twirpTurboghas.GetBillableUsersResponse{
		BillableEntityId:   1,
		BillableEntityType: twirpTurboghas.EntityType_ENTITY_TYPE_BUSINESS,
		UserIds:            []uint64{1},
	}, nil).Once()

	deps := mocks.Cleanup(t, &mockDeps{})
	deps.On("GetEmailsFromRefUpdates", mocks.IsContext, uint64(1), []*githubv1.PostReceive_RefUpdate{
		{RefName: "refs/heads/main", PreviousRefOid: "4d39ee7d0836ac8c17a662685db03a85fa845a4f", CurrentRefOid: "3161860805acb9e11eadfddb6e92274ba00158ac"},
	}).Return([]*commits.Contributor{
		{EmailBytes: []byte("user@example.com"), CommitOid: &types.ObjectID{Id: "4d39ee7d0836ac8c17a662685db03a85fa845a4f"}},
	}, nil).Once()

	msg := &githubv1.PostReceive{
		PushedAt: now,
		Actor: &entitiesv1.User{
			Login: "ghost",
		},
		Business: &githubv1.PostReceive_Business{},
		Repository: &entitiesv1.Repository{
			Id:         1,
			Visibility: entitiesv1.Repository_PRIVATE,
		},
		Owner: &entitiesv1.User{
			Id:    1,
			Login: "monalisa",
			Type:  entitiesv1.User_ORGANIZATION,
		},
		RefUpdates: []*githubv1.PostReceive_RefUpdate{
			{RefName: "refs/heads/main", PreviousRefOid: "4d39ee7d0836ac8c17a662685db03a85fa845a4f", CurrentRefOid: "3161860805acb9e11eadfddb6e92274ba00158ac"},
		},
	}

	p := processor.New(d, api, nil, nil, deps)

	require.NoError(t, p.ProcessMessage(ctx, msg))
}

func TestPostReceiveNotEnabled(t *testing.T) {
	db := dbtest.RequireConnection(t)
	d := dbtest.Data(db)
	ctx := context.Background()

	flipper := mocks.Cleanup(t, &mocks.Flipper{})
	flipper.On("IsEnabled", mocks.IsContext, "turboghas_entity_too_large", "User:1").Return(true, nil).Once()

	ctx = fromctx.Flipper.With(ctx, flipper)

	msg := &githubv1.PostReceive{
		PushedAt: timestamppb.Now(),
		Actor: &entitiesv1.User{
			Login: "ghost",
		},
		Business: &githubv1.PostReceive_Business{},
		Repository: &entitiesv1.Repository{
			Id:         1,
			Visibility: entitiesv1.Repository_PRIVATE,
		},
		Owner: &entitiesv1.User{
			Id:    1,
			Login: "monalisa",
			Type:  entitiesv1.User_ORGANIZATION,
		},
		RefUpdates: []*githubv1.PostReceive_RefUpdate{
			{RefName: "refs/heads/main", PreviousRefOid: "4d39ee7d0836ac8c17a662685db03a85fa845a4f", CurrentRefOid: "3161860805acb9e11eadfddb6e92274ba00158ac"},
		},
	}

	require.NoError(t, processor.New(d, &mockApi{}, &mockPublisher{}, nil, &mockDeps{}).ProcessMessage(ctx, msg))
}
