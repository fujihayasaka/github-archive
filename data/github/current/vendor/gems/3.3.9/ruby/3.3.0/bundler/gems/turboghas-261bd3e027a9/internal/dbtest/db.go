// Package dbtest provides connections to the test database, wrapped in transactions.
package dbtest

import (
	"bytes"
	"context"
	"database/sql"
	"fmt"
	"os"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/github/hydro-client-go/v7/pkg/hydro"
	githubv1 "github.com/github/hydro-schemas-go/hydro/schemas/github/v1"
	entitiesv1 "github.com/github/hydro-schemas-go/hydro/schemas/github/v1/entities"
	"github.com/github/spokes-proto/gen/go/v1/commits"
	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/github/turboghas/internal/data"
	"github.com/github/turboghas/internal/fromctx"
	"github.com/github/turboghas/internal/mocks"
	twirpTurboghas "github.com/github/turboghas/internal/monolith_twirp/turboghas/v1"
	"github.com/github/turboghas/internal/mysql_dual"
	"github.com/github/turboghas/internal/processor"
	"github.com/go-sql-driver/mysql"
	"github.com/simon-engledew/sqlh"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/reflect/protoreflect"
	"google.golang.org/protobuf/types/known/timestamppb"
	"google.golang.org/protobuf/types/known/wrapperspb"
)

func Config() *mysql.Config {
	cfg := mysql.NewConfig()
	cfg.Net = "tcp"
	cfg.User = "root"
	if fromctx.IsGitHubCodespace {
		cfg.DBName = "github_test_turboghas"
		cfg.Addr = "localhost:3306"
	} else {
		cfg.DBName = "turboghas_test"
		cfg.Addr = "localhost:13806"
	}
	cfg.ParseTime = true
	cfg.InterpolateParams = true // forces statements to be prepared client-side see https://github.com/github/database-infrastructure/issues/2260#issuecomment-538617856
	cfg.Collation = "utf8mb4_general_ci"
	cfg.MultiStatements = false
	cfg.CheckConnLiveness = true
	cfg.ClientFoundRows = true
	cfg.Params = map[string]string{
		"charset": "utf8mb4",
	}

	return cfg
}

func must[T any](tb testing.TB) func(v T, err error) T {
	tb.Helper()
	return func(v T, err error) T {
		require.NoError(tb, err)
		return v
	}
}

func copyDB(tb testing.TB, cfg *mysql.Config, dest string) {
	tb.Helper()

	db, err := sql.Open("mysql", cfg.FormatDSN())
	require.NoError(tb, err)
	defer func() {
		require.NoError(tb, db.Close())
	}()

	mustExec := must[sql.Result](tb)

	mustExec(db.Exec(fmt.Sprintf(`DROP DATABASE IF EXISTS %s`, dest)))
	mustExec(db.Exec(fmt.Sprintf(`CREATE DATABASE %s`, dest)))

	var tables []string

	require.NoError(tb, db.QueryRow(`SELECT json_arrayagg(table_name) FROM  information_schema.tables WHERE table_schema = ?`, cfg.DBName).Scan(sqlh.Json(&tables)))

	for _, table := range tables {
		mustExec(db.Exec(fmt.Sprintf("CREATE TABLE %s.%s LIKE %s.%s", dest, table, cfg.DBName, table)))
	}
}

var counter atomic.Uint64

func RequireConnection(tb testing.TB) *sql.DB {
	tb.Helper()

	cfg := Config()

	tmpDB := fmt.Sprintf(`%s_tmp_%d_%d`, cfg.DBName, os.Getpid(), counter.Add(1))

	copyDB(tb, cfg, tmpDB)

	cfg.DBName = tmpDB

	db, err := sql.Open("mysql", cfg.FormatDSN())
	require.NoError(tb, err)
	tb.Cleanup(func() {
		_, err := db.Exec(fmt.Sprintf(`DROP DATABASE IF EXISTS %s`, tmpDB))
		require.NoError(tb, err)
		require.NoError(tb, db.Close())
	})

	require.NoError(tb, db.Ping())

	return db
}

func Dual(db *sql.DB) *mysql_dual.Connection {
	// todo: create a read only connection to test the replica
	rdb := mysql_dual.NewRetryDB(db)
	return &mysql_dual.Connection{
		Primary: mysql_dual.NewThrottleDB(rdb),
		Replica: rdb,
	}
}

func RequireScan[V any](t *testing.T, row *sql.Row) V {
	t.Helper()
	var v V
	require.NoError(t, row.Scan(&v))
	return v
}

type mockUser struct {
	*twirpTurboghas.GetUsersResponse_User
	id uint64
}

type mockRepo struct {
	*twirpTurboghas.GetRepositoriesResponse_Repository
	id uint64
}

type mockApi struct {
	users map[uint64]mockUser
	repos map[uint64]mockRepo
}

// this is so that gopls can help us generate the missing mock methods.
var _ twirpTurboghas.TurboghasAPI = &mockApi{}

// GetEntities implements v1.TurboghasAPI.
func (*mockApi) GetEntities(context.Context, *twirpTurboghas.GetEntitiesRequest) (*twirpTurboghas.GetEntitiesResponse, error) {
	panic("unimplemented")
}

// GetRepositories implements v1.TurboghasAPI.
func (m *mockApi) GetRepositories(_ context.Context, request *twirpTurboghas.GetRepositoriesRequest) (*twirpTurboghas.GetRepositoriesResponse, error) {
	resp := twirpTurboghas.GetRepositoriesResponse{
		Repositories: map[uint64]*twirpTurboghas.GetRepositoriesResponse_Repository{},
	}
	for _, repoID := range request.RepositoryIds {
		if repo, ok := m.repos[repoID]; ok {
			if owner, ok := m.users[repo.OwnerId]; ok {
				if repo, ok := proto.Clone(repo).(*twirpTurboghas.GetRepositoriesResponse_Repository); ok {
					repo.Owner = owner.GetUsersResponse_User
					resp.Repositories[repoID] = repo
				}
			}
		}
	}
	return &resp, nil
}

// GetUsers implements v1.TurboghasAPI.
func (m *mockApi) GetUsers(ctx context.Context, request *twirpTurboghas.GetUsersRequest) (*twirpTurboghas.GetUsersResponse, error) {
	resp := twirpTurboghas.GetUsersResponse{
		Users: map[uint64]*twirpTurboghas.GetUsersResponse_User{},
	}
	for _, userID := range request.UserIds {
		if user, ok := m.users[userID]; ok {
			resp.Users[userID] = user.GetUsersResponse_User
		}
	}
	return &resp, nil
}

func (m *mockApi) FindUsersByEmails(ctx context.Context, request *twirpTurboghas.FindUsersByEmailsRequest) (*twirpTurboghas.FindUsersByEmailsResponse, error) {
	out := make([]*twirpTurboghas.FindUsersByEmailsResponse_User, 0, len(request.Emails))
	for _, email := range request.Emails {
		login := string(email[:bytes.IndexByte(email, '@')])
		for userID, user := range m.users {
			if login == user.Login {
				out = append(out, &twirpTurboghas.FindUsersByEmailsResponse_User{
					Email: email,
					Login: user.Login,
					Id:    userID,
				})
			}
		}
	}
	return &twirpTurboghas.FindUsersByEmailsResponse{
		Users: out,
	}, nil
}

func (m *mockApi) GetBillableUsers(ctx context.Context, request *twirpTurboghas.GetBillableUsersRequest) (*twirpTurboghas.GetBillableUsersResponse, error) {
	if request.OwnerId == 52 {
		return &twirpTurboghas.GetBillableUsersResponse{
			BillableEntityId:   2,
			BillableEntityType: twirpTurboghas.EntityType_ENTITY_TYPE_BUSINESS,
			UserIds:            []uint64{50},
		}, nil
	}
	if request.OwnerId == 53 {
		return &twirpTurboghas.GetBillableUsersResponse{
			BillableEntityId:   53,
			BillableEntityType: twirpTurboghas.EntityType_ENTITY_TYPE_USER,
			UserIds:            []uint64{51},
		}, nil
	}
	var userIDs []uint64
	for userID, user := range m.users {
		if strings.HasSuffix(user.Login, "-billable") {
			userIDs = append(userIDs, userID)
		}
	}
	return &twirpTurboghas.GetBillableUsersResponse{
		BillableEntityId:   1,
		BillableEntityType: twirpTurboghas.EntityType_ENTITY_TYPE_BUSINESS,
		UserIds:            userIDs,
	}, nil
}

type mockDeps struct {
}

var _ processor.Dependencies = &mockDeps{}

func (m *mockDeps) GetEmailsFromRefUpdates(ctx context.Context, repositoryID uint64, refUpdates []*githubv1.PostReceive_RefUpdate) ([]*commits.Contributor, error) {
	out := make([]*commits.Contributor, 0, len(refUpdates))
	for _, refUpdate := range refUpdates {
		out = append(out, &commits.Contributor{
			EmailBytes: []byte(strings.TrimPrefix(refUpdate.RefName, "refs/heads/")),
			CommitOid:  &types.ObjectID{Id: refUpdate.CurrentRefOid},
		})
	}
	return out, nil
}

type mockPublisher struct {
	mock.Mock
}

func (m *mockPublisher) Publish(msg protoreflect.ProtoMessage, opts ...hydro.PublishOption) error {
	args := m.Called(msg, opts)
	return args.Error(0)
}

func newMockApi(t *testing.T, users map[uint64]string, repos map[uint64]string) *mockApi {
	t.Helper()
	api := &mockApi{
		users: make(map[uint64]mockUser),
		repos: make(map[uint64]mockRepo),
	}
	for userID, login := range users {
		t := twirpTurboghas.UserType_USER_TYPE_USER
		if strings.HasPrefix(login, "org-") {
			t = twirpTurboghas.UserType_USER_TYPE_ORGANIZATION
		}
		api.users[userID] = mockUser{
			GetUsersResponse_User: &twirpTurboghas.GetUsersResponse_User{
				Login:               login,
				Type:                t,
				IsEnterpriseManaged: strings.HasPrefix(login, "emu-"),
			},
			id: userID,
		}
	}
outer:
	for repoID, nwo := range repos {
		parts := strings.SplitN(nwo, "/", 2)
		require.Len(t, parts, 2)
		ownerLogin, repoName := parts[0], parts[1]
		for ownerID, owner := range api.users {
			if owner.Login == ownerLogin {
				api.repos[repoID] = mockRepo{
					GetRepositoriesResponse_Repository: &twirpTurboghas.GetRepositoriesResponse_Repository{
						Entity: &twirpTurboghas.GetRepositoriesResponse_Entity{
							Id:   1,
							Type: twirpTurboghas.EntityType_ENTITY_TYPE_BUSINESS,
						},
						AdvancedSecurityEnabled: strings.HasPrefix(repoName, "enabled-"),
						Name:                    repoName,
						OwnerId:                 ownerID,
						Owner:                   owner.GetUsersResponse_User,
					},
					id: repoID,
				}
				continue outer
			}
		}
		require.Fail(t, "failed to find owner for repository")
	}
	return api
}

func oldContribution(d time.Duration) func(*githubv1.PostReceive) {
	return func(msg *githubv1.PostReceive) {
		msg.PushedAt = timestamppb.New(msg.PushedAt.AsTime().Add(-d))
	}
}

func mockPush(user mockUser, repo mockRepo, opts ...func(*githubv1.PostReceive)) *githubv1.PostReceive {
	ownerType := entitiesv1.User_ORGANIZATION
	if repo.Owner.IsEnterpriseManaged {
		ownerType = entitiesv1.User_USER
	}
	msg := &githubv1.PostReceive{
		PushedAt: timestamppb.Now(),
		Actor: &entitiesv1.User{
			Login: user.Login,
		},
		Business: &githubv1.PostReceive_Business{
			Id: &wrapperspb.Int32Value{Value: 1},
		},
		Repository: &entitiesv1.Repository{
			Id:         uint32(repo.id),
			Name:       repo.Name,
			Visibility: entitiesv1.Repository_PRIVATE,
		},
		Owner: &entitiesv1.User{
			Id:                  uint32(repo.OwnerId),
			Login:               repo.Owner.Login,
			Type:                ownerType,
			IsEnterpriseManaged: repo.Owner.IsEnterpriseManaged,
		},
		RefUpdates: []*githubv1.PostReceive_RefUpdate{
			{RefName: fmt.Sprintf("refs/heads/%s@example.com", user.Login), PreviousRefOid: "4d39ee7d0836ac8c17a662685db03a85fa845a4f", CurrentRefOid: "3161860805acb9e11eadfddb6e92274ba00158ac"},
		},
	}
	for _, opt := range opts {
		opt(msg)
	}
	return msg
}

func Data(db *sql.DB) *data.Data {
	return data.New(Dual(db))
}

func Seed(t *testing.T) *sql.DB {
	t.Helper()

	ctx := context.Background()
	db := RequireConnection(t)
	d := Data(db)
	pub := mocks.Cleanup(t, &mockPublisher{})

	api := newMockApi(t,
		// users
		map[uint64]string{
			1: "user-1-billable",
			2: "user-2-billable",
			3: "user-3",
			4: "user-4-billable",
			5: "user-5-billable",
			6: "emu-6-billable", // EMU user
			// An EMU user that only contributes to repos without advanced security (an additional committer)
			7:  "emu-7-billable",
			8:  "user-8",
			9:  "user-9-billable",
			10: "user-10-billable",
			// Organizations
			101: "org-1",
			102: "org-2",
			// Outsider data that should not appear in any cassette requests.
			50: "user-50",
			51: "user-51",
			52: "org-52",
			53: "org-53",
		},
		// repos
		map[uint64]string{
			1:  "org-1/enabled-repo-1",
			2:  "org-2/repo-2",
			3:  "org-1/enabled-repo-3",
			4:  "org-2/enabled-repo-4",
			10: "org-1/repo-10",
			11: "emu-6-billable/enabled-repo-11", // EMU repository
			12: "emu-6-billable/repo-12",         // EMU repository without advanced security
		},
	)

	api.users[52] = mockUser{
		GetUsersResponse_User: &twirpTurboghas.GetUsersResponse_User{
			Login:     "org-52",
			Type:      twirpTurboghas.UserType_USER_TYPE_ORGANIZATION,
			CreatedAt: timestamppb.Now(),
		},
		id: 52,
	}
	api.users[53] = mockUser{
		GetUsersResponse_User: &twirpTurboghas.GetUsersResponse_User{
			Login:     "org-53",
			Type:      twirpTurboghas.UserType_USER_TYPE_ORGANIZATION,
			CreatedAt: timestamppb.Now(),
		},
		id: 53,
	}

	api.repos[50] = mockRepo{
		GetRepositoriesResponse_Repository: &twirpTurboghas.GetRepositoriesResponse_Repository{
			Entity: &twirpTurboghas.GetRepositoriesResponse_Entity{
				Id:   2,
				Type: twirpTurboghas.EntityType_ENTITY_TYPE_BUSINESS,
			},
			AdvancedSecurityEnabled: true,
			Name:                    "business-owned-repo",
			OwnerId:                 52,
			Owner:                   api.users[52].GetUsersResponse_User,
		},
		id: 50,
	}
	api.repos[51] = mockRepo{
		GetRepositoriesResponse_Repository: &twirpTurboghas.GetRepositoriesResponse_Repository{
			Entity: &twirpTurboghas.GetRepositoriesResponse_Entity{
				Id:   53,
				Type: twirpTurboghas.EntityType_ENTITY_TYPE_USER,
			},
			AdvancedSecurityEnabled: true,
			Name:                    "org-owned-repo",
			OwnerId:                 53,
			Owner:                   api.users[53].GetUsersResponse_User,
		},
		id: 51,
	}

	p := processor.New(d, api, pub, nil, &mockDeps{})

	pub.Mock.On("Publish", mock.Anything, mock.Anything).Run(func(args mock.Arguments) {
		msg, ok := args.Get(0).(protoreflect.ProtoMessage)
		require.True(t, ok)
		require.NoError(t, p.ProcessMessage(ctx, msg))
	}).Return(nil)

	for _, msg := range []*githubv1.PostReceive{
		// user-1 @ org-101/test-1
		mockPush(api.users[1], api.repos[1]),
		// user-8 @ org-101/test-1
		mockPush(api.users[8], api.repos[1]),
		// user-9 @ org-1/test-1
		mockPush(api.users[9], api.repos[1]),
		// user-5 @ org-101/test-1
		mockPush(api.users[5], api.repos[1]),
		// user-1 @ org-101/test-3
		mockPush(api.users[1], api.repos[3]),
		// user-5 @ org-101/test-10
		mockPush(api.users[5], api.repos[10]),
		// user-2 @ org-102/test-2
		mockPush(api.users[2], api.repos[2]),
		// user-4 @ org-102/test-2
		mockPush(api.users[4], api.repos[2], oldContribution(101*24*time.Hour)), // stale commit
		// user-3 @ org-102/test-2
		mockPush(api.users[3], api.repos[2]),
		// user-9 @ org-2/test-2
		mockPush(api.users[9], api.repos[2]),
		// user-10 @ org-2/test-2
		mockPush(api.users[10], api.repos[2]),
		// user-5 @ org-102/test-4
		mockPush(api.users[5], api.repos[4]),
		// user-6 @ emu-6/test-11
		mockPush(api.users[6], api.repos[11]),
		// user-7 @ emu-7/test-12
		mockPush(api.users[7], api.repos[12]),
		// Outsider data that should not appear in any cassette requests.
		mockPush(api.users[50], api.repos[50], func(p *githubv1.PostReceive) {
			p.Business.Id = wrapperspb.Int32(2)
		}),
		mockPush(api.users[51], api.repos[50], func(p *githubv1.PostReceive) {
			p.Business.Id = wrapperspb.Int32(2)
		}),
		mockPush(api.users[51], api.repos[51], func(p *githubv1.PostReceive) {
			p.Business = nil
		}),
	} {
		t.Logf("%15s committing to %s/%s\n", msg.Actor.Login, msg.Owner.Login, msg.Repository.Name)
		require.NoError(t, p.ProcessMessage(ctx, msg))
	}

	require.NoError(t, p.ProcessMessage(ctx, &githubv1.RepositoryDeleted{
		Actor: &entitiesv1.User{
			Login: "user-5",
		},
		DeletedRepository: &entitiesv1.Repository{
			Id:   10,
			Name: "test-10",
		},
	}))

	return db
}
