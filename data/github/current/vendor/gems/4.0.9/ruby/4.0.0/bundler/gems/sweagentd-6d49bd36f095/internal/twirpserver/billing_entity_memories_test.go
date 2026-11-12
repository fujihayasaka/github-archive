package twirpserver

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/github/sweagentd/internal/featureflags"
	memorycore "github.com/github/sweagentd/internal/memory/core"
	jobs_pb "github.com/github/sweagentd/proto/jobs/v1"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
	"google.golang.org/protobuf/types/known/timestamppb"
)

type mockBillingEntityMemoryService struct {
	filter      memorycore.BillingEntityMemoryFilter
	pageRequest memorycore.MemoryPageRequest
	page        *memorycore.MemoryPage
	err         error
	calls       int
}

func (m *mockBillingEntityMemoryService) ListBillingEntityMemories(_ context.Context, filter memorycore.BillingEntityMemoryFilter, pageRequest memorycore.MemoryPageRequest) (*memorycore.MemoryPage, error) {
	m.calls++
	m.filter = filter
	m.pageRequest = pageRequest
	return m.page, m.err
}

func (m *mockBillingEntityMemoryService) DeleteBillingEntityMemories(_ context.Context, filter memorycore.BillingEntityMemoryFilter, pageRequest memorycore.MemoryPageRequest) (*memorycore.BillingEntityDeleteResult, error) {
	m.calls++
	m.filter = filter
	m.pageRequest = pageRequest
	return &memorycore.BillingEntityDeleteResult{}, m.err
}

func TestListUserMemoriesForBillingEntityValidation(t *testing.T) {
	snapshotTime := timestamppb.New(time.Date(2025, time.January, 2, 3, 4, 5, 0, time.UTC))
	tests := []struct {
		name     string
		req      *jobs_pb.ListUserMemoriesForBillingEntityRequest
		code     twirp.ErrorCode
		argument string
	}{
		{
			name:     "missing request",
			req:      nil,
			code:     twirp.InvalidArgument,
			argument: "request",
		},
		{
			name: "missing snapshot_time",
			req: &jobs_pb.ListUserMemoriesForBillingEntityRequest{
				UserId:         42,
				OrganizationId: 100,
			},
			code:     twirp.InvalidArgument,
			argument: "snapshot_time",
		},
		{
			name: "missing user_id",
			req: &jobs_pb.ListUserMemoriesForBillingEntityRequest{
				OrganizationId: 100,
				SnapshotTime:   snapshotTime,
			},
			code:     twirp.InvalidArgument,
			argument: "user_id",
		},
		{
			name: "missing billing entity",
			req: &jobs_pb.ListUserMemoriesForBillingEntityRequest{
				UserId:       42,
				SnapshotTime: snapshotTime,
			},
			code:     twirp.InvalidArgument,
			argument: "organization_id",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			service := &mockBillingEntityMemoryService{}
			server := newBillingEntityMemoryTestServer(service, true)

			_, err := server.ListUserMemoriesForBillingEntity(context.Background(), tt.req)

			requireTwirpCode(t, err, tt.code)
			requireTwirpArgument(t, err, tt.argument)
			require.Zero(t, service.calls)
		})
	}
}

func TestListUserMemoriesForBillingEntityRequiresConfiguredService(t *testing.T) {
	server := newBillingEntityMemoryTestServer(nil, true)

	_, err := server.ListUserMemoriesForBillingEntity(context.Background(), &jobs_pb.ListUserMemoriesForBillingEntityRequest{
		UserId:         42,
		OrganizationId: 100,
		SnapshotTime:   timestamppb.Now(),
	})

	requireTwirpCode(t, err, twirp.Internal)
}

func TestListUserMemoriesForBillingEntityCallsServiceAndMapsResponse(t *testing.T) {
	createdAt := time.Date(2025, time.January, 2, 3, 4, 5, 0, time.UTC)
	updatedAt := createdAt.Add(time.Hour)
	snapshotTime := createdAt.Add(24 * time.Hour)
	service := &mockBillingEntityMemoryService{
		page: &memorycore.MemoryPage{
			Memories: []*memorycore.Memory{
				{
					ID:        memorycore.MemoryID("mem-1"),
					Subject:   "subject",
					Fact:      "fact",
					Citations: []string{"citation-1", "citation-2"},
					Reason:    "reason",
					Source: memorycore.MemorySource{
						InteractionID: "interaction-1",
						User:          memorycore.User{ID: 42, Login: "octocat"},
						Agent:         "copilot",
						CommitSHA:     "abc123",
						BaseModel:     "gpt-test",
					},
					CreatedAt: createdAt,
					UpdatedAt: updatedAt,
				},
			},
			ContinuationToken: "next-token",
		},
	}
	server := newBillingEntityMemoryTestServer(service, true)

	resp, err := server.ListUserMemoriesForBillingEntity(context.Background(), &jobs_pb.ListUserMemoriesForBillingEntityRequest{
		UserId:            42,
		OrganizationId:    100,
		EnterpriseId:      200,
		Limit:             5000,
		ContinuationToken: "current-token",
		SnapshotTime:      timestamppb.New(snapshotTime),
	})

	require.NoError(t, err)
	require.Equal(t, 1, service.calls)
	require.Equal(t, memorycore.BillingEntityMemoryFilter{OrganizationID: 100, EnterpriseID: 200, UserID: 42}, service.filter)
	require.Equal(t, memorycore.MemoryPageRequest{Limit: maxBillingEntityMemoryPageLimit, ContinuationToken: "current-token", SnapshotTime: snapshotTime}, service.pageRequest)
	require.Equal(t, "next-token", resp.GetContinuationToken())
	require.Len(t, resp.GetMemories(), 1)

	memory := resp.GetMemories()[0]
	require.Equal(t, "mem-1", memory.GetId())
	require.Equal(t, "subject", memory.GetSubject())
	require.Equal(t, "fact", memory.GetFact())
	require.Equal(t, []string{"citation-1", "citation-2"}, memory.GetCitations())
	require.Equal(t, "reason", memory.GetReason())
	require.Equal(t, "interaction-1", memory.GetSource().GetInteractionId())
	require.Equal(t, "copilot", memory.GetSource().GetAgent())
	require.Equal(t, "abc123", memory.GetSource().GetCommitSha())
	require.Equal(t, "gpt-test", memory.GetSource().GetBaseModel())
	require.Equal(t, uint64(42), memory.GetSource().GetUserId())
	require.Equal(t, "octocat", memory.GetSource().GetUserLogin())
	require.True(t, memory.GetCreatedAt().AsTime().Equal(createdAt))
	require.True(t, memory.GetUpdatedAt().AsTime().Equal(updatedAt))
}

func TestListUserMemoriesForBillingEntityDefaultsLimit(t *testing.T) {
	service := &mockBillingEntityMemoryService{page: &memorycore.MemoryPage{}}
	server := newBillingEntityMemoryTestServer(service, true)
	snapshotTime := time.Date(2025, time.January, 2, 3, 4, 5, 0, time.UTC)

	_, err := server.ListUserMemoriesForBillingEntity(context.Background(), &jobs_pb.ListUserMemoriesForBillingEntityRequest{
		UserId:         42,
		OrganizationId: 100,
		SnapshotTime:   timestamppb.New(snapshotTime),
	})

	require.NoError(t, err)
	require.Equal(t, memorycore.MemoryPageRequest{Limit: defaultBillingEntityMemoryPageLimit, SnapshotTime: snapshotTime}, service.pageRequest)
}

func TestListUserMemoriesForBillingEntityMapsServiceErrors(t *testing.T) {
	tests := []struct {
		name     string
		err      error
		code     twirp.ErrorCode
		argument string
	}{
		{
			name:     "invalid billing filter",
			err:      memorycore.ErrInvalidBillingFilter,
			code:     twirp.InvalidArgument,
			argument: "organization_id",
		},
		{
			name:     "invalid user filter",
			err:      memorycore.ErrInvalidUserFilter,
			code:     twirp.InvalidArgument,
			argument: "user_id",
		},
		{
			name:     "invalid snapshot time",
			err:      memorycore.ErrInvalidSnapshotTime,
			code:     twirp.InvalidArgument,
			argument: "snapshot_time",
		},
		{
			name:     "invalid continuation token",
			err:      memorycore.ErrInvalidContinuation,
			code:     twirp.InvalidArgument,
			argument: "continuation_token",
		},
		{
			name: "memory store throttled",
			err:  memorycore.ErrMemoryStoreThrottled,
			code: twirp.ResourceExhausted,
		},
		{
			name: "store failure",
			err:  errors.New("store failed"),
			code: twirp.Internal,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			service := &mockBillingEntityMemoryService{err: tt.err}
			server := newBillingEntityMemoryTestServer(service, true)

			_, err := server.ListUserMemoriesForBillingEntity(context.Background(), &jobs_pb.ListUserMemoriesForBillingEntityRequest{
				UserId:         42,
				OrganizationId: 100,
				SnapshotTime:   timestamppb.Now(),
			})

			requireTwirpCode(t, err, tt.code)
			if tt.argument != "" {
				requireTwirpArgument(t, err, tt.argument)
			}
		})
	}
}

func TestListUserMemoriesForBillingEntityRequiresFeatureFlag(t *testing.T) {
	service := &mockBillingEntityMemoryService{}
	server := newBillingEntityMemoryTestServer(service, false)

	_, err := server.ListUserMemoriesForBillingEntity(context.Background(), &jobs_pb.ListUserMemoriesForBillingEntityRequest{
		UserId:         42,
		OrganizationId: 100,
		SnapshotTime:   timestamppb.Now(),
	})

	requireTwirpCode(t, err, twirp.NotFound)
	require.Zero(t, service.calls)
}

func TestBillingEntityMemoryExportActors(t *testing.T) {
	actors := billingEntityMemoryExportActors(memorycore.BillingEntityMemoryFilter{
		OrganizationID: 100,
		EnterpriseID:   200,
		UserID:         42,
	})

	require.Len(t, actors, 2)
	require.Equal(t, "Organization:100", actors[0].VexiID())
	require.Equal(t, "Business:200", actors[1].VexiID())
}

func newBillingEntityMemoryTestServer(service memoryService, enabled bool) *Server {
	server := &Server{
		ffClient: featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotMemoryAdminExports: enabled,
		}),
	}
	if service != nil {
		server.WithMemoryService(service)
	}
	return server
}

func requireTwirpCode(t *testing.T, err error, code twirp.ErrorCode) {
	t.Helper()

	var twirpErr twirp.Error
	require.ErrorAs(t, err, &twirpErr)
	require.Equal(t, code, twirpErr.Code())
}

func requireTwirpArgument(t *testing.T, err error, argument string) {
	t.Helper()

	var twirpErr twirp.Error
	require.ErrorAs(t, err, &twirpErr)
	require.Equal(t, argument, twirpErr.Meta("argument"))
}
