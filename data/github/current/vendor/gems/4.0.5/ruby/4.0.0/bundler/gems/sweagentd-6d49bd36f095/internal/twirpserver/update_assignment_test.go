package twirpserver

import (
	"context"
	"errors"
	"testing"

	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobs/store"
	"github.com/github/sweagentd/internal/jobs/store/memory"
	"github.com/github/sweagentd/internal/observability"
	jobs_pb "github.com/github/sweagentd/proto/jobs/v1"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
)

func setupUpdateAssignmentTestServer(t *testing.T) (*Server, *memory.Store) {
	t.Helper()

	obsv := observability.NewNoopExporters()
	store := memory.NewStore()

	server := &Server{
		obsv:     obsv,
		jobStore: store,
	}

	return server, store
}

func createTestAssignment(t *testing.T, store *memory.Store, ownerID, repoID int64) *jobs.Assignment {
	t.Helper()

	assignment := jobs.NewAssignment(ownerID, repoID, "owner-node-id", "repo-node-id", "owner", "repo", false)
	created, err := store.CreateAssignment(context.Background(), assignment)
	require.NoError(t, err)
	return created
}

func TestUpdateAssignment_SetsPullRequest(t *testing.T) {
	server, store := setupUpdateAssignmentTestServer(t)
	assignment := createTestAssignment(t, store, 123, 456)

	req := &jobs_pb.UpdateAssignmentRequest{
		AssignmentId:      assignment.ID,
		OwnerId:           123,
		RepoId:            456,
		PullRequestId:     1001,
		PullRequestNumber: 42,
	}

	resp, err := server.UpdateAssignment(context.Background(), req)
	require.NoError(t, err)
	require.NotNil(t, resp)

	// Verify the assignment was updated in the store.
	updated, err := store.GetAssignment(context.Background(), 123, 456, assignment.ID)
	require.NoError(t, err)
	assert.Equal(t, int64(1001), updated.PullRequestID)
	assert.Equal(t, 42, updated.PullRequestNumber)
}

func TestUpdateAssignment_Idempotent(t *testing.T) {
	server, store := setupUpdateAssignmentTestServer(t)
	assignment := createTestAssignment(t, store, 123, 456)

	req := &jobs_pb.UpdateAssignmentRequest{
		AssignmentId:      assignment.ID,
		OwnerId:           123,
		RepoId:            456,
		PullRequestId:     1001,
		PullRequestNumber: 42,
	}

	// First call sets the PR fields.
	_, err := server.UpdateAssignment(context.Background(), req)
	require.NoError(t, err)

	// Capture the ETag after the first write.
	afterFirst, err := store.GetAssignment(context.Background(), 123, 456, assignment.ID)
	require.NoError(t, err)
	assert.Equal(t, int64(1001), afterFirst.PullRequestID)
	assert.Equal(t, 42, afterFirst.PullRequestNumber)
	etagAfterFirst := afterFirst.ETag

	// Second call with same data: should succeed without writing.
	resp, err := server.UpdateAssignment(context.Background(), req)
	require.NoError(t, err)
	require.NotNil(t, resp)

	// ETag must be unchanged — no write occurred.
	afterSecond, err := store.GetAssignment(context.Background(), 123, 456, assignment.ID)
	require.NoError(t, err)
	assert.Equal(t, etagAfterFirst, afterSecond.ETag, "idempotent call must not update the assignment")
}

func TestUpdateAssignment_IdempotentPartialFields(t *testing.T) {
	server, store := setupUpdateAssignmentTestServer(t)
	assignment := createTestAssignment(t, store, 123, 456)

	// Set only the PR ID.
	req := &jobs_pb.UpdateAssignmentRequest{
		AssignmentId:  assignment.ID,
		OwnerId:       123,
		RepoId:        456,
		PullRequestId: 1001,
	}

	// First call sets the PR ID.
	_, err := server.UpdateAssignment(context.Background(), req)
	require.NoError(t, err)

	// Capture the ETag after the first write.
	afterFirst, err := store.GetAssignment(context.Background(), 123, 456, assignment.ID)
	require.NoError(t, err)
	etagAfterFirst := afterFirst.ETag

	// Second call with same PR ID only: should succeed without writing.
	resp, err := server.UpdateAssignment(context.Background(), req)
	require.NoError(t, err)
	require.NotNil(t, resp)

	// ETag must be unchanged — no write occurred.
	afterSecond, err := store.GetAssignment(context.Background(), 123, 456, assignment.ID)
	require.NoError(t, err)
	assert.Equal(t, etagAfterFirst, afterSecond.ETag, "idempotent call must not update the assignment")
}

func TestUpdateAssignment_NoFieldsToUpdate(t *testing.T) {
	server, store := setupUpdateAssignmentTestServer(t)
	assignment := createTestAssignment(t, store, 123, 456)

	// Capture the ETag before the call.
	initial, err := store.GetAssignment(context.Background(), 123, 456, assignment.ID)
	require.NoError(t, err)
	etagBefore := initial.ETag

	req := &jobs_pb.UpdateAssignmentRequest{
		AssignmentId: assignment.ID,
		OwnerId:      123,
		RepoId:       456,
		// No patchable fields set — should return success without writing.
	}

	resp, err := server.UpdateAssignment(context.Background(), req)
	require.NoError(t, err)
	require.NotNil(t, resp)

	// ETag must be unchanged — no write occurred.
	afterCall, err := store.GetAssignment(context.Background(), 123, 456, assignment.ID)
	require.NoError(t, err)
	assert.Equal(t, etagBefore, afterCall.ETag, "call with no fields must not update the assignment")
}

func TestUpdateAssignment_NotFound(t *testing.T) {
	server, _ := setupUpdateAssignmentTestServer(t)

	req := &jobs_pb.UpdateAssignmentRequest{
		AssignmentId:      "nonexistent-id",
		OwnerId:           123,
		RepoId:            456,
		PullRequestId:     1001,
		PullRequestNumber: 42,
	}

	_, err := server.UpdateAssignment(context.Background(), req)
	require.Error(t, err)

	var twerr twirp.Error
	require.True(t, errors.As(err, &twerr))
	assert.Equal(t, twirp.NotFound, twerr.Code())
}

func TestUpdateAssignment_StoreInternalError(t *testing.T) {
	obsv := observability.NewNoopExporters()
	failingStore := &alwaysFailGetAssignmentStore{}
	server := &Server{
		obsv:     obsv,
		jobStore: failingStore,
	}

	req := &jobs_pb.UpdateAssignmentRequest{
		AssignmentId:  "some-id",
		OwnerId:       123,
		RepoId:        456,
		PullRequestId: 1001,
	}

	_, err := server.UpdateAssignment(context.Background(), req)
	require.Error(t, err)

	var twerr twirp.Error
	require.True(t, errors.As(err, &twerr))
	// Internal store failure should return Internal, not NotFound.
	assert.Equal(t, twirp.Internal, twerr.Code())
}

func TestUpdateAssignment_ValidatesFields(t *testing.T) {
	server, _ := setupUpdateAssignmentTestServer(t)

	testCases := []struct {
		name          string
		req           *jobs_pb.UpdateAssignmentRequest
		expectedField string
	}{
		{
			name: "missing assignment_id",
			req: &jobs_pb.UpdateAssignmentRequest{
				OwnerId: 123,
				RepoId:  456,
			},
			expectedField: "assignment_id",
		},
		{
			name: "missing owner_id",
			req: &jobs_pb.UpdateAssignmentRequest{
				AssignmentId: "some-id",
				RepoId:       456,
			},
			expectedField: "owner_id",
		},
		{
			name: "missing repo_id",
			req: &jobs_pb.UpdateAssignmentRequest{
				AssignmentId: "some-id",
				OwnerId:      123,
			},
			expectedField: "repo_id",
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			_, err := server.UpdateAssignment(context.Background(), tc.req)
			require.Error(t, err)

			var twerr twirp.Error
			require.True(t, errors.As(err, &twerr))
			assert.Equal(t, twirp.InvalidArgument, twerr.Code())
			assert.Contains(t, twerr.Meta("argument"), tc.expectedField)
		})
	}
}

func TestUpdateAssignment_PreconditionFailed_DesiredStateAlreadyApplied(t *testing.T) {
	obsv := observability.NewNoopExporters()
	// First GetAssignment returns stale data (PR fields unset) so needsUpdate is true.
	// PatchAssignment fails with ErrPreconditionFailedOnUpdate (concurrent update).
	// Second GetAssignment (re-fetch) returns the desired state already applied.
	stubStore := &preconditionFailStore{
		firstGet: &jobs.Assignment{
			ID:      "assignment-1",
			OwnerID: 123,
			RepoID:  456,
		},
		refetchGet: &jobs.Assignment{
			ID:                "assignment-1",
			OwnerID:           123,
			RepoID:            456,
			PullRequestID:     1001,
			PullRequestNumber: 42,
		},
	}
	server := &Server{obsv: obsv, jobStore: stubStore}

	req := &jobs_pb.UpdateAssignmentRequest{
		AssignmentId:      "assignment-1",
		OwnerId:           123,
		RepoId:            456,
		PullRequestId:     1001,
		PullRequestNumber: 42,
	}

	// Should succeed because re-fetch shows desired state is already applied.
	resp, err := server.UpdateAssignment(context.Background(), req)
	require.NoError(t, err)
	require.NotNil(t, resp)
}

func TestUpdateAssignment_PreconditionFailed_ConflictingState(t *testing.T) {
	obsv := observability.NewNoopExporters()
	// First GetAssignment returns stale data so needsUpdate is true.
	// PatchAssignment fails with ErrPreconditionFailedOnUpdate.
	// Re-fetch shows a different concurrent update was applied (not our values).
	stubStore := &preconditionFailStore{
		firstGet: &jobs.Assignment{
			ID:      "assignment-1",
			OwnerID: 123,
			RepoID:  456,
		},
		refetchGet: &jobs.Assignment{
			ID:                "assignment-1",
			OwnerID:           123,
			RepoID:            456,
			PullRequestID:     9999,
			PullRequestNumber: 99,
		},
	}
	server := &Server{obsv: obsv, jobStore: stubStore}

	req := &jobs_pb.UpdateAssignmentRequest{
		AssignmentId:      "assignment-1",
		OwnerId:           123,
		RepoId:            456,
		PullRequestId:     1001,
		PullRequestNumber: 42,
	}

	_, err := server.UpdateAssignment(context.Background(), req)
	require.Error(t, err)

	var twerr twirp.Error
	require.True(t, errors.As(err, &twerr))
	assert.Equal(t, twirp.Aborted, twerr.Code())
	assert.Contains(t, twerr.Msg(), "concurrent update conflict")
}

// alwaysFailGetAssignmentStore is a minimal store stub that returns a non-NotFound error from GetAssignment.
type alwaysFailGetAssignmentStore struct {
	memory.Store
}

func (f *alwaysFailGetAssignmentStore) GetAssignment(_ context.Context, _, _ int64, _ string) (*jobs.Assignment, error) {
	return nil, errors.New("connection refused")
}

var _ store.JobsStore = (*alwaysFailGetAssignmentStore)(nil)

// preconditionFailStore stubs GetAssignment to return different assignments on
// the first vs second call (simulating a concurrent update between read and write),
// and PatchAssignment to always return ErrPreconditionFailedOnUpdate.
type preconditionFailStore struct {
	memory.Store

	firstGet   *jobs.Assignment
	refetchGet *jobs.Assignment
	getCalls   int
}

func (f *preconditionFailStore) GetAssignment(_ context.Context, _, _ int64, _ string) (*jobs.Assignment, error) {
	f.getCalls++
	if f.getCalls == 1 {
		return f.firstGet, nil
	}
	return f.refetchGet, nil
}

func (f *preconditionFailStore) PatchAssignment(_ context.Context, _ *jobs.Assignment, _ store.AssignmentPatch, _ ...store.PatchAssignmentOption) error {
	return store.NewErrPreconditionFailedOnUpdate()
}

var _ store.JobsStore = (*preconditionFailStore)(nil)
