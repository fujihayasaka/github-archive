package handlers

import (
	"context"
	"strings"
	"testing"
	"time"

	dependencygraphv1 "github.com/github/dependency-snapshots-api/hydro/schemas/github/dependencygraph/v1"
	"github.com/github/dependency-snapshots-api/hydro/schemas/github/v1/entities"
	mockenqueuer "github.com/github/dependency-snapshots-api/internal/aqueduct/mock"
	"github.com/github/dependency-snapshots-api/internal/config"
	mockstatter "github.com/github/dependency-snapshots-api/internal/testutil/mock"
	"github.com/github/dependency-snapshots-api/pkg/proto/jobs"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	hydroclient "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	"github.com/segmentio/ksuid"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/timestamppb"
	"google.golang.org/protobuf/types/known/wrapperspb"
)

const previousSHA = "defg5678"
const currentSHA = "abcd1234"

func TestRepositoryPushHandler_DropsEventIfFeatureDisabled(t *testing.T) {
	ctx := context.Background()
	cfg := &config.Config{}
	logger := log.NewNullLogger()
	mockStatter := mockstatter.MockedStatter{}
	mockEnqueuer := mockenqueuer.MockedEnqueuer{}

	// Expecting dropped event stat increment
	mockStatter.On("Counter", mock.Anything, mock.Anything, mock.Anything).Return().Once()

	handler := NewRepositoryPushHandler(cfg, logger, &mockStatter, &mockEnqueuer)

	testEnvelope := envelope(t,
		&dependencygraphv1.RepositoryPush{
			Repository: &entities.Repository{
				Id: 123,
			},
		})

	err := handler.HandleEnvelope(ctx, testEnvelope)
	require.NoError(t, err)

	mockStatter.AssertExpectations(t)

	// Expecting no job to be enqueued
	mockEnqueuer.AssertNotCalled(t, "Enqueue", mock.Anything, mock.Anything)
}

func TestRepositoryPushHandler_DropsEventIfFeaturesClientBroken(t *testing.T) {
	ctx := context.Background()
	cfg := &config.Config{}
	logger := log.NewNullLogger()
	mockStatter := mockstatter.MockedStatter{}
	mockEnqueuer := mockenqueuer.MockedEnqueuer{}

	// Expecting dropped event stat increment
	mockStatter.On("Counter", mock.Anything, mock.Anything, mock.Anything).Return().Once()

	handler := NewRepositoryPushHandler(cfg, logger, &mockStatter, &mockEnqueuer)

	testEnvelope := envelope(t,
		&dependencygraphv1.RepositoryPush{
			Repository: &entities.Repository{
				Id: 123,
			},
		})

	err := handler.HandleEnvelope(ctx, testEnvelope)
	require.NoError(t, err)

	mockStatter.AssertExpectations(t)

	// Expecting no job to be enqueued
	mockEnqueuer.AssertNotCalled(t, "Enqueue", mock.Anything, mock.Anything)
}

func TestRepositoryPushHandler_DependabotSnapshotInitJob(t *testing.T) {
	ctx := context.Background()
	cfg := &config.Config{}
	logger := log.NewNullLogger()
	mockStatter := mockstatter.MockedStatter{}
	mockEnqueuer := mockenqueuer.MockedEnqueuer{}

	// Expecting job to be enqueued
	mockEnqueuer.On("Enqueue",
		mock.Anything,
		mock.MatchedBy(func(j *jobs.DependabotSnapshotInitJob) bool {
			require.Equal(t, uint32(123), j.GetRepository().GetId())
			require.Equal(t, "refs/heads/main", j.GetRef())
			require.Equal(t, true, j.GetIsDefaultBranch())
			require.Equal(t, jobs.DependabotSnapshotInitJob_TRIGGERED_BY_PUSH, j.GetTriggeredBy())
			return true
		}),
	).Return(ksuid.New().String(), nil).Once()

	// Expecting successful submission metrics to be recorded
	mockStatter.On("Counter", mock.Anything, mock.Anything, mock.Anything).Return().Once()

	handler := NewRepositoryPushHandler(cfg, logger, &mockStatter, &mockEnqueuer)

	testMsg := newRepositoryPushInitPushMsg()
	testEnvelope := envelope(t, &testMsg)

	err := handler.HandleEnvelope(ctx, testEnvelope)
	require.NoError(t, err)

	mockEnqueuer.AssertExpectations(t)
	mockStatter.AssertExpectations(t)
}

// A DependabotSnapshotPostPush job should be dispatched for every ref in every eligible repo-push event received.
func TestRepositoryPushHandler_DependabotSnapshotPostPush(t *testing.T) {
	ctx := context.Background()
	cfg := &config.Config{}
	logger := log.NewNullLogger()
	mockStatter := mockstatter.MockedStatter{}
	mockEnqueuer := mockenqueuer.MockedEnqueuer{}

	// Expecting job to be enqueued
	mockEnqueuer.On("Enqueue",
		mock.Anything,
		mock.MatchedBy(func(j *jobs.DependabotSnapshotPostPushJob) bool {
			require.Equal(t, uint32(123), j.GetRepository().GetId())
			require.Equal(t, "refs/heads/main", j.GetRef())
			require.Equal(t, previousSHA, j.GetBeforeOid())
			require.Equal(t, currentSHA, j.GetAfterOid())
			require.Equal(t, true, j.GetIsDefaultBranch())
			require.Equal(t, jobs.DependabotSnapshotPostPushJob_TRIGGERED_BY_PUSH, j.GetTriggeredBy())
			require.NotNil(t, j.PushId, "push_id should be propagated")
			require.Equal(t, uint64(42), j.GetPushId())
			return true
		}),
	).Return(ksuid.New().String(), nil).Once()

	// Expecting successful submission metrics to be recorded
	mockStatter.On("Counter", mock.Anything, mock.Anything, mock.Anything).Return().Once()

	handler := NewRepositoryPushHandler(cfg, logger, &mockStatter, &mockEnqueuer)

	testMsg := newRepositoryPushMsg()
	testEnvelope := envelope(t, &testMsg)

	err := handler.HandleEnvelope(ctx, testEnvelope)
	require.NoError(t, err)

	mockEnqueuer.AssertExpectations(t)
	mockStatter.AssertExpectations(t)
}

// A push_id of zero should be treated as absent and not propagated to the job.
func TestRepositoryPushHandler_ZeroPushIDDropped(t *testing.T) {
	ctx := context.Background()
	cfg := &config.Config{}
	logger := log.NewNullLogger()
	mockStatter := mockstatter.MockedStatter{}
	mockEnqueuer := mockenqueuer.MockedEnqueuer{}

	// Expecting job to be enqueued with nil push_id
	mockEnqueuer.On("Enqueue",
		mock.Anything,
		mock.MatchedBy(func(j *jobs.DependabotSnapshotPostPushJob) bool {
			require.Nil(t, j.PushId, "zero push_id should not be propagated")
			return true
		}),
	).Return(ksuid.New().String(), nil).Once()

	// Expecting successful submission metrics to be recorded
	mockStatter.On("Counter", mock.Anything, mock.Anything, mock.Anything).Return().Once()

	handler := NewRepositoryPushHandler(cfg, logger, &mockStatter, &mockEnqueuer)

	testMsg := dependencygraphv1.RepositoryPush{
		RequestContext: &entities.RequestContext{
			RequestId: "testrequest",
		},
		Repository: &entities.Repository{
			Id:            123,
			DefaultBranch: "main",
		},
		RefUpdates: []*dependencygraphv1.RepositoryPush_RefUpdates{
			{
				RefName:        "refs/heads/main",
				PreviousRefOid: previousSHA,
				CurrentRefOid:  currentSHA,
				PushedAt:       halloween,
				PushId:         wrapperspb.Int64(0),
			},
		},
	}
	testEnvelope := envelope(t, &testMsg)

	err := handler.HandleEnvelope(ctx, testEnvelope)
	require.NoError(t, err)

	mockEnqueuer.AssertExpectations(t)
	mockStatter.AssertExpectations(t)
}

func TestRepositoryPushHandler_PushDeletesRef(t *testing.T) {
	ctx := context.Background()
	cfg := &config.Config{}
	logger := log.NewNullLogger()
	mockStatter := stats.NullStatter
	mockEnqueuer := mockenqueuer.MockedEnqueuer{}

	handler := NewRepositoryPushHandler(cfg, logger, mockStatter, &mockEnqueuer)

	testMsg := newRepositoryPushDeletedRefMsg()
	testEnvelope := envelope(t, &testMsg)

	err := handler.HandleEnvelope(ctx, testEnvelope)
	require.NoError(t, err)

	mockEnqueuer.AssertExpectations(t)
	mockEnqueuer.AssertNotCalled(t, "Enqueue", mock.Anything)
}

func TestRepositoryPushHandler_NonDefaultBranch(t *testing.T) {
	ctx := context.Background()
	cfg := &config.Config{}
	logger := log.NewNullLogger()
	mockStatter := stats.NullStatter
	mockEnqueuer := mockenqueuer.MockedEnqueuer{}

	handler := NewRepositoryPushHandler(cfg, logger, mockStatter, &mockEnqueuer)

	testMsg := newRepositoryPushWithNonDefaultRefs()
	testEnvelope := envelope(t, &testMsg)

	err := handler.HandleEnvelope(ctx, testEnvelope)
	require.NoError(t, err)

	mockEnqueuer.AssertExpectations(t)
	mockEnqueuer.AssertNotCalled(t, "Enqueue", mock.Anything)
}

func TestGetBranchDiffs_MultipleRefs(t *testing.T) {
	cfg := &config.Config{}
	logger := log.NewNullLogger()
	statter := stats.NullStatter
	mockEnqueuer := mockenqueuer.MockedEnqueuer{}

	handler := NewRepositoryPushHandler(cfg, logger, statter, &mockEnqueuer)

	testMsg := newRepositoryPushWithMultipleRefs()

	diffs, err := handler.getRefUpdates("refs/heads/main", &testMsg)

	require.NoError(t, err)

	for _, diff := range diffs {
		require.True(t, strings.HasPrefix(diff.RefName, "refs/heads/"))
		if diff.RefName == "refs/heads/main" {
			require.Equal(t, diff.IsDefaultBranch, true)
			require.Equal(t, previousSHA, diff.BeforeOID)
			require.Equal(t, currentSHA, diff.AfterOID)
		} else {
			require.NotEmpty(t, diff.BeforeOID)
			require.NotEmpty(t, diff.AfterOID)
			require.False(t, diff.IsDefaultBranch)
		}
	}
}

func TestEligiblePush(t *testing.T) {
	cfg := &config.Config{}
	logger := log.NewNullLogger()
	statter := stats.NullStatter
	mockEnqueuer := mockenqueuer.MockedEnqueuer{}

	handler := NewRepositoryPushHandler(cfg, logger, statter, &mockEnqueuer)

	unprocessable := []func() dependencygraphv1.RepositoryPush{spammyMsg, archivedMsg}
	for _, f := range unprocessable {
		msg := f()
		result := handler.eligiblePush(&msg)
		require.Equal(t, false, result)
	}
}

func TestRepositoryPushHandler_RequestIDPresent(t *testing.T) {
	ctx := context.Background()
	cfg := &config.Config{}
	logger := log.NewNullLogger()
	statter := stats.NullStatter
	mockEnqueuer := mockenqueuer.MockedEnqueuer{}

	// Expecting job to be enqueued with correct Request ID
	mockEnqueuer.On("Enqueue",
		mock.Anything,
		mock.MatchedBy(func(j *jobs.DependabotSnapshotPostPushJob) bool {
			return j.GetRequestId() == "req:ues:t"
		}),
	).Return(ksuid.New().String(), nil).Once()

	handler := NewRepositoryPushHandler(cfg, logger, statter, &mockEnqueuer)

	testMsg := postPushWithRequestID()
	testEnvelope := envelope(t, &testMsg)

	err := handler.HandleEnvelope(ctx, testEnvelope)
	require.NoError(t, err)
}

func TestRepositoryPushHandler_RequestIDGeneration(t *testing.T) {
	ctx := context.Background()
	cfg := &config.Config{}
	logger := log.NewNullLogger()
	statter := stats.NullStatter
	mockEnqueuer := mockenqueuer.MockedEnqueuer{}

	// Expecting job to be enqueued with correct Request ID
	mockEnqueuer.On("Enqueue",
		mock.Anything,
		mock.MatchedBy(func(j *jobs.DependabotSnapshotPostPushJob) bool {
			return len(j.GetRequestId()) == 27 // The ksuid is always 27 characters long (base 62)
		}),
	).Return(ksuid.New().String(), nil).Once()

	handler := NewRepositoryPushHandler(cfg, logger, statter, &mockEnqueuer)
	testMsg := postPushWithoutRequestID()
	testEnvelope := envelope(t, &testMsg)

	err := handler.HandleEnvelope(ctx, testEnvelope)
	require.NoError(t, err)
}

func envelope(t *testing.T, msg proto.Message) *hydroclient.Envelope {
	t.Helper()
	encoded, err := proto.Marshal(msg)
	require.NoError(t, err)
	return &hydroclient.Envelope{
		TypeUrl:   "",
		Message:   encoded,
		Id:        "",
		Timestamp: &timestamppb.Timestamp{},
		Site:      0,
		SiteName:  "",
	}
}

var halloween = timestamppb.New(time.Date(2023, 10, 31, 0, 0, 0, 0, time.UTC))

func newRepositoryPushMsg() dependencygraphv1.RepositoryPush {
	return dependencygraphv1.RepositoryPush{
		RequestContext: &entities.RequestContext{
			RequestId: "testrequest",
		},
		Repository: &entities.Repository{
			Id:            123,
			DefaultBranch: "main",
		},
		RefUpdates: []*dependencygraphv1.RepositoryPush_RefUpdates{
			{
				RefName:        "refs/heads/main",
				PreviousRefOid: previousSHA,
				CurrentRefOid:  currentSHA,
				PushedAt:       halloween,
				PushId:         wrapperspb.Int64(42),
			},
		},
	}
}

func newRepositoryPushWithMultipleRefs() dependencygraphv1.RepositoryPush {
	return dependencygraphv1.RepositoryPush{
		RequestContext: &entities.RequestContext{
			RequestId: "testrequest",
		},
		Repository: &entities.Repository{
			Id:            123,
			DefaultBranch: "main",
		},
		RefUpdates: []*dependencygraphv1.RepositoryPush_RefUpdates{
			{
				RefName:        "refs/heads/master",
				PreviousRefOid: "bace4321",
				CurrentRefOid:  "aced6789",
				PushedAt:       halloween,
			},
			{
				RefName:        "refs/heads/main",
				PreviousRefOid: previousSHA,
				CurrentRefOid:  currentSHA,
				PushedAt:       halloween,
			},
			{
				RefName:        "refs/heads/master",
				PreviousRefOid: "a68b939",
				CurrentRefOid:  "358ec18",
				PushedAt:       halloween,
			},
			{
				RefName:        "refs/tags/sometag",
				PreviousRefOid: "a68b939",
				CurrentRefOid:  "358ec18",
				PushedAt:       halloween,
			},
		},
	}
}

func newRepositoryPushWithNonDefaultRefs() dependencygraphv1.RepositoryPush {
	return dependencygraphv1.RepositoryPush{
		RequestContext: &entities.RequestContext{
			RequestId: "testrequest",
		},
		Repository: &entities.Repository{
			Id:            123,
			DefaultBranch: "main",
		},
		RefUpdates: []*dependencygraphv1.RepositoryPush_RefUpdates{
			{
				RefName:        "refs/heads/development",
				PreviousRefOid: "bace4321",
				CurrentRefOid:  "aced6789",
				PushedAt:       halloween,
			},
			{
				RefName:        "refs/heads/testing",
				PreviousRefOid: "a68b939",
				CurrentRefOid:  "358ec18",
				PushedAt:       halloween,
			},
		},
	}
}

func archivedMsg() dependencygraphv1.RepositoryPush {
	return dependencygraphv1.RepositoryPush{
		RequestContext: &entities.RequestContext{
			RequestId: "testrequest",
		},
		Repository: &entities.Repository{
			Id:            123,
			DefaultBranch: "main",
			IsArchived:    true,
		},
		RefUpdates: []*dependencygraphv1.RepositoryPush_RefUpdates{
			{
				RefName:        "refs/heads/main",
				PreviousRefOid: previousSHA,
				CurrentRefOid:  currentSHA,
				PushedAt:       halloween,
			},
		},
	}
}

func postPushWithoutRequestID() dependencygraphv1.RepositoryPush {
	return dependencygraphv1.RepositoryPush{
		RequestContext: &entities.RequestContext{
			RequestId: "",
		},
		Repository: &entities.Repository{
			Id:            123,
			DefaultBranch: "main",
			IsFork:        false,
		},
		RefUpdates: []*dependencygraphv1.RepositoryPush_RefUpdates{
			{
				RefName:        "refs/heads/main",
				PreviousRefOid: previousSHA,
				CurrentRefOid:  currentSHA,
				PushedAt:       halloween,
			},
		},
	}
}

func postPushWithRequestID() dependencygraphv1.RepositoryPush {
	return dependencygraphv1.RepositoryPush{
		RequestContext: &entities.RequestContext{
			RequestId: "req:ues:t",
		},
		Repository: &entities.Repository{
			Id:            123,
			DefaultBranch: "main",
			IsFork:        false,
		},
		RefUpdates: []*dependencygraphv1.RepositoryPush_RefUpdates{
			{
				RefName:        "refs/heads/main",
				PreviousRefOid: previousSHA,
				CurrentRefOid:  currentSHA,
				PushedAt:       halloween,
			},
		},
	}
}

func spammyMsg() dependencygraphv1.RepositoryPush {
	return dependencygraphv1.RepositoryPush{
		RequestContext: &entities.RequestContext{
			RequestId: "testing-something",
		},
		Repository: &entities.Repository{
			Id:            123,
			DefaultBranch: "main",
			IsFork:        false,
		},
		Owner: &entities.User{
			Spammy: true,
		},
		RefUpdates: []*dependencygraphv1.RepositoryPush_RefUpdates{
			{
				RefName:        "refs/heads/main",
				PreviousRefOid: previousSHA,
				CurrentRefOid:  currentSHA,
				PushedAt:       halloween,
			},
		},
	}

}

func newRepositoryPushInitPushMsg() dependencygraphv1.RepositoryPush {
	return dependencygraphv1.RepositoryPush{
		RequestContext: &entities.RequestContext{
			RequestId: "testrequest",
		},
		Repository: &entities.Repository{
			Id:            123,
			DefaultBranch: "main",
		},
		RefUpdates: []*dependencygraphv1.RepositoryPush_RefUpdates{
			{
				RefName:        "refs/heads/main",
				PreviousRefOid: ZeroOID,
				CurrentRefOid:  currentSHA,
				PushedAt:       halloween,
			},
		},
	}
}

func newRepositoryPushDeletedRefMsg() dependencygraphv1.RepositoryPush {
	return dependencygraphv1.RepositoryPush{
		RequestContext: &entities.RequestContext{
			RequestId: "testrequest",
		},
		Repository: &entities.Repository{
			Id:            123,
			DefaultBranch: "main",
		},
		RefUpdates: []*dependencygraphv1.RepositoryPush_RefUpdates{
			{
				RefName:        "refs/heads/main",
				PreviousRefOid: previousSHA,
				CurrentRefOid:  ZeroOID,
				PushedAt:       halloween,
			},
		},
	}
}
