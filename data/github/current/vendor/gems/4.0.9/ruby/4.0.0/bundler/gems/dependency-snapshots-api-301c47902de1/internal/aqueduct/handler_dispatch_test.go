package aqueduct

import (
	"context"
	"testing"

	aq "github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/dependency-snapshots-api/internal/config"
	"github.com/github/dependency-snapshots-api/internal/features"
	"github.com/github/dependency-snapshots-api/internal/gitaccess"
	"github.com/github/dependency-snapshots-api/internal/hydro"
	"github.com/github/dependency-snapshots-api/internal/interfaces"
	jobsproto "github.com/github/dependency-snapshots-api/pkg/proto/jobs"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/github-telemetry-go/trace"
	"github.com/github/go-stats"
	"github.com/stretchr/testify/assert"
	"google.golang.org/protobuf/proto"
)

// helper to build handler with minimal deps
func newTestHandler(statter stats.Client) *JobHandler {
	return NewDSAPIJobHandler(&config.Config{}, log.NewNullLogger(), statter, nil, nil, nil, nil, nil, nil)
}

func TestDispatchRoutesInit(t *testing.T) {
	ctx := context.Background()

	called := false
	var gotJob *jobsproto.DependabotSnapshotInitJob
	old := handleDependabotSnapshotInitJob
	handleDependabotSnapshotInitJob = func(_ context.Context, _ *config.Config, _ log.Logger, _ stats.Client, _ *trace.Tracer, _ gitaccess.Client, _ hydro.Publisher, _ features.Client, _ interfaces.DependabotEventService, job *jobsproto.DependabotSnapshotInitJob) error {
		called = true
		gotJob = job
		return nil
	}
	defer func() { handleDependabotSnapshotInitJob = old }()

	payload, _ := proto.Marshal(&jobsproto.DependabotSnapshotInitJob{
		Repository: &jobsproto.DependabotSnapshotInitJob_Repository{Id: 123},
	})
	handler := newTestHandler(stats.NullStatter)

	if err := handler.HandlerFn(ctx, aq.ReceiveResult{Job: aq.Job{Queue: DependabotSnapshotInitQueue, Payload: payload}}); err != nil {
		t.Fatalf("handler returned error: %v", err)
	}

	if !called {
		t.Fatalf("init handler was not invoked")
	}
	if gotJob.GetRepository().GetId() != 123 {
		t.Fatalf("unexpected repo id: %d", gotJob.GetRepository().GetId())
	}
}

func TestDispatchRoutesPostPush(t *testing.T) {
	ctx := context.Background()

	called := false
	old := handleDependabotSnapshotPostPushJob
	handleDependabotSnapshotPostPushJob = func(_ context.Context, _ *config.Config, _ log.Logger, _ stats.Client, _ *trace.Tracer, _ gitaccess.Client, _ hydro.Publisher, _ features.Client, _ interfaces.DependabotEventService, _ *jobsproto.DependabotSnapshotPostPushJob) error {
		called = true
		return nil
	}
	defer func() { handleDependabotSnapshotPostPushJob = old }()

	payload, _ := proto.Marshal(&jobsproto.DependabotSnapshotPostPushJob{
		Repository: &jobsproto.DependabotSnapshotPostPushJob_Repository{Id: 456},
	})
	handler := newTestHandler(stats.NullStatter)

	if err := handler.HandlerFn(ctx, aq.ReceiveResult{Job: aq.Job{Queue: DependabotSnapshotPostPushQueue, Payload: payload}}); err != nil {
		t.Fatalf("handler returned error: %v", err)
	}

	if !called {
		t.Fatalf("post-push handler was not invoked")
	}
}

func TestDispatchRoutesUpdateGraphComputeUsage(t *testing.T) {
	ctx := context.Background()

	called := false
	old := handleUpdateGraphComputeUsageJob
	handleUpdateGraphComputeUsageJob = func(_ context.Context, _ *config.Config, _ log.Logger, _ stats.Client, job *jobsproto.UpdateGraphComputeUsageJob) error {
		called = true
		if job.GetRepositoryId() != 789 {
			t.Fatalf("unexpected repo id: %d", job.GetRepositoryId())
		}
		return nil
	}
	defer func() { handleUpdateGraphComputeUsageJob = old }()

	payload, _ := proto.Marshal(&jobsproto.UpdateGraphComputeUsageJob{RepositoryId: 789})
	handler := newTestHandler(stats.NullStatter)

	if err := handler.HandlerFn(ctx, aq.ReceiveResult{Job: aq.Job{Queue: UpdateGraphComputeUsageQueue, Payload: payload}}); err != nil {
		t.Fatalf("handler returned error: %v", err)
	}

	if !called {
		t.Fatalf("update-graph compute usage handler was not invoked")
	}
}

func TestDispatchUnknownQueue(t *testing.T) {
	ctx := context.Background()
	mst := stats.NullStatter

	handler := newTestHandler(mst)

	err := handler.HandlerFn(ctx, aq.ReceiveResult{Job: aq.Job{Queue: "weird", Payload: []byte("irrelevant")}})
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "unknown queue")
}

func TestDispatchUnmarshalError(t *testing.T) {
	ctx := context.Background()
	mst := stats.NullStatter

	handler := newTestHandler(mst)

	err := handler.HandlerFn(ctx, aq.ReceiveResult{Job: aq.Job{Queue: DependabotSnapshotInitQueue, Payload: []byte("bad bytes")}})
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "unmarshal init job")
}
