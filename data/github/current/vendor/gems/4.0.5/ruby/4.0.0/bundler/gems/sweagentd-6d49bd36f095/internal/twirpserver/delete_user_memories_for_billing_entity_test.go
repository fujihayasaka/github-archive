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

type mockDeleteBillingEntityMemoryService struct {
	filter      memorycore.BillingEntityMemoryFilter
	pageRequest memorycore.MemoryPageRequest
	result      *memorycore.BillingEntityDeleteResult
	err         error
	calls       int
}

func (m *mockDeleteBillingEntityMemoryService) ListBillingEntityMemories(_ context.Context, _ memorycore.BillingEntityMemoryFilter, _ memorycore.MemoryPageRequest) (*memorycore.MemoryPage, error) {
	return &memorycore.MemoryPage{}, nil
}

func (m *mockDeleteBillingEntityMemoryService) DeleteBillingEntityMemories(_ context.Context, filter memorycore.BillingEntityMemoryFilter, pageRequest memorycore.MemoryPageRequest) (*memorycore.BillingEntityDeleteResult, error) {
	m.calls++
	m.filter = filter
	m.pageRequest = pageRequest
	return m.result, m.err
}

func TestDeleteUserMemoriesForBillingEntityValidation(t *testing.T) {
	snapshotTime := timestamppb.New(time.Date(2025, time.January, 2, 3, 4, 5, 0, time.UTC))
	tests := []struct {
		name     string
		req      *jobs_pb.DeleteUserMemoriesForBillingEntityRequest
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
			name: "missing user_id",
			req: &jobs_pb.DeleteUserMemoriesForBillingEntityRequest{
				OrganizationId: 100,
				SnapshotTime:   snapshotTime,
			},
			code:     twirp.InvalidArgument,
			argument: "user_id",
		},
		{
			name: "missing snapshot_time",
			req: &jobs_pb.DeleteUserMemoriesForBillingEntityRequest{
				UserId:         42,
				OrganizationId: 100,
			},
			code:     twirp.InvalidArgument,
			argument: "snapshot_time",
		},
		{
			name: "missing billing entity",
			req: &jobs_pb.DeleteUserMemoriesForBillingEntityRequest{
				UserId:       42,
				SnapshotTime: snapshotTime,
			},
			code:     twirp.InvalidArgument,
			argument: "organization_id",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			service := &mockDeleteBillingEntityMemoryService{}
			server := newDeleteBillingEntityMemoryTestServer(service, true)

			_, err := server.DeleteUserMemoriesForBillingEntity(context.Background(), tt.req)

			requireTwirpCode(t, err, tt.code)
			requireTwirpArgument(t, err, tt.argument)
			require.Zero(t, service.calls)
		})
	}
}

func TestDeleteUserMemoriesForBillingEntityRequiresConfiguredService(t *testing.T) {
	server := newDeleteBillingEntityMemoryTestServer(nil, true)

	_, err := server.DeleteUserMemoriesForBillingEntity(context.Background(), &jobs_pb.DeleteUserMemoriesForBillingEntityRequest{
		UserId:         42,
		OrganizationId: 100,
		SnapshotTime:   timestamppb.Now(),
	})

	requireTwirpCode(t, err, twirp.Internal)
}

func TestDeleteUserMemoriesForBillingEntityRequiresFeatureFlag(t *testing.T) {
	service := &mockDeleteBillingEntityMemoryService{}
	server := newDeleteBillingEntityMemoryTestServer(service, false)

	_, err := server.DeleteUserMemoriesForBillingEntity(context.Background(), &jobs_pb.DeleteUserMemoriesForBillingEntityRequest{
		UserId:         42,
		OrganizationId: 100,
		SnapshotTime:   timestamppb.Now(),
	})

	requireTwirpCode(t, err, twirp.NotFound)
	require.Zero(t, service.calls)
}

func TestDeleteUserMemoriesForBillingEntityCallsServiceAndMapsResponse(t *testing.T) {
	snapshotTime := time.Date(2025, time.January, 2, 3, 4, 5, 0, time.UTC)
	service := &mockDeleteBillingEntityMemoryService{
		result: &memorycore.BillingEntityDeleteResult{
			DeletedCount:      5,
			ContinuationToken: "next-token",
		},
	}
	server := newDeleteBillingEntityMemoryTestServer(service, true)

	resp, err := server.DeleteUserMemoriesForBillingEntity(context.Background(), &jobs_pb.DeleteUserMemoriesForBillingEntityRequest{
		UserId:            42,
		OrganizationId:    100,
		EnterpriseId:      200,
		Limit:             5000, // should be clamped to max
		ContinuationToken: "current-token",
		SnapshotTime:      timestamppb.New(snapshotTime),
	})

	require.NoError(t, err)
	require.Equal(t, 1, service.calls)
	require.Equal(t, memorycore.BillingEntityMemoryFilter{OrganizationID: 100, EnterpriseID: 200, UserID: 42}, service.filter)
	require.Equal(t, memorycore.MemoryPageRequest{Limit: maxBillingEntityMemoryDeleteLimit, ContinuationToken: "current-token", SnapshotTime: snapshotTime}, service.pageRequest)
	require.Equal(t, uint32(5), resp.GetDeletedCount())
	require.Equal(t, "next-token", resp.GetContinuationToken())
}

func TestDeleteUserMemoriesForBillingEntityDefaultsLimit(t *testing.T) {
	service := &mockDeleteBillingEntityMemoryService{result: &memorycore.BillingEntityDeleteResult{}}
	server := newDeleteBillingEntityMemoryTestServer(service, true)
	snapshotTime := time.Date(2025, time.January, 2, 3, 4, 5, 0, time.UTC)

	_, err := server.DeleteUserMemoriesForBillingEntity(context.Background(), &jobs_pb.DeleteUserMemoriesForBillingEntityRequest{
		UserId:         42,
		OrganizationId: 100,
		SnapshotTime:   timestamppb.New(snapshotTime),
	})

	require.NoError(t, err)
	require.Equal(t, memorycore.MemoryPageRequest{Limit: defaultBillingEntityMemoryDeleteLimit, SnapshotTime: snapshotTime}, service.pageRequest)
}

func TestDeleteUserMemoriesForBillingEntityMapsServiceErrors(t *testing.T) {
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
			name: "unexpected store failure",
			err:  errors.New("store failed"),
			code: twirp.Internal,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			service := &mockDeleteBillingEntityMemoryService{err: tt.err}
			server := newDeleteBillingEntityMemoryTestServer(service, true)

			_, err := server.DeleteUserMemoriesForBillingEntity(context.Background(), &jobs_pb.DeleteUserMemoriesForBillingEntityRequest{
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

func newDeleteBillingEntityMemoryTestServer(service memoryService, enabled bool) *Server {
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
