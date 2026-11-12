package stopagentcomputejob

import (
	"context"
	"testing"

	"github.com/github/aqueduct-client-go/v3/pkg/aqueduct"
	"github.com/github/sweagentd/internal/aqueduct/jobs"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

type stopCall struct {
	computeID string
	actorID   uint64
}

type fakeSandboxStopper struct {
	stopFn func(ctx context.Context, id string, actor uint64) error
	calls  []stopCall
}

func (f *fakeSandboxStopper) StopSandbox(ctx context.Context, computeID string, actorID uint64) error {
	f.calls = append(f.calls, stopCall{computeID: computeID, actorID: actorID})
	if f.stopFn != nil {
		return f.stopFn(ctx, computeID, actorID)
	}
	return nil
}

type isCurrentCall struct {
	computeID  string
	generation int64
}

type fakeGuard struct {
	isCurrentFn func(computeID string, generation int64) bool
	calls       []isCurrentCall
}

func (f *fakeGuard) IsCurrent(computeID string, generation int64) bool {
	f.calls = append(f.calls, isCurrentCall{computeID: computeID, generation: generation})
	if f.isCurrentFn != nil {
		return f.isCurrentFn(computeID, generation)
	}
	return true
}

func newCtx() context.Context {
	return requestctx.NewContext(context.Background())
}

func marshalJob(ctx context.Context, t *testing.T, computeID string, actorID, generation int64) []byte {
	t.Helper()
	job := jobs.NewStopAgentComputeJob(ctx, computeID, actorID, generation)
	payload, err := job.Marshal()
	require.NoError(t, err)
	return payload
}

func TestHandlerUnknownQueueReturnsError(t *testing.T) {
	obsv := observability.NewNoopExporters()
	stopper := &fakeSandboxStopper{}
	guard := &fakeGuard{}
	handler := Handler(obsv, stopper, guard)

	ctx := newCtx()
	rr := aqueduct.ReceiveResult{
		Job: aqueduct.Job{
			ID:      "job-1",
			Queue:   "some-other-queue",
			Payload: []byte{},
		},
	}

	_, err := handler(ctx, rr)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "unknown queue")
	assert.Empty(t, stopper.calls)
}

func TestHandlerUnmarshalFailureReturnsError(t *testing.T) {
	obsv := observability.NewNoopExporters()
	stopper := &fakeSandboxStopper{}
	handler := Handler(obsv, stopper, &fakeGuard{})

	rr := aqueduct.ReceiveResult{
		Job: aqueduct.Job{
			ID:      "job-1",
			Queue:   jobs.StopAgentComputeJobQueueName,
			Payload: []byte{0xff, 0xff, 0xff},
		},
	}

	_, err := handler(newCtx(), rr)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "unmarshal")
	assert.Empty(t, stopper.calls)
}

func TestHandlerEmptyComputeIDIsDropped(t *testing.T) {
	obsv := observability.NewNoopExporters()
	stopper := &fakeSandboxStopper{}
	guard := &fakeGuard{}
	handler := Handler(obsv, stopper, guard)

	ctx := newCtx()
	payload := marshalJob(ctx, t, "", 42, 1)

	rr := aqueduct.ReceiveResult{
		Job: aqueduct.Job{
			ID:      "job-1",
			Queue:   jobs.StopAgentComputeJobQueueName,
			Payload: payload,
		},
	}

	_, err := handler(ctx, rr)
	require.NoError(t, err)
	assert.Empty(t, stopper.calls)
	assert.Empty(t, guard.calls)
}

func TestHandlerSupersededGenerationSkips(t *testing.T) {
	obsv := observability.NewNoopExporters()
	stopper := &fakeSandboxStopper{}
	guard := &fakeGuard{
		isCurrentFn: func(string, int64) bool { return false },
	}
	handler := Handler(obsv, stopper, guard)

	ctx := newCtx()
	payload := marshalJob(ctx, t, "compute-1", 42, 7)

	rr := aqueduct.ReceiveResult{
		Job: aqueduct.Job{
			ID:      "job-1",
			Queue:   jobs.StopAgentComputeJobQueueName,
			Payload: payload,
		},
	}

	_, err := handler(ctx, rr)
	require.NoError(t, err)
	assert.Empty(t, stopper.calls)
	require.Len(t, guard.calls, 1)
	assert.Equal(t, "compute-1", guard.calls[0].computeID)
	assert.Equal(t, int64(7), guard.calls[0].generation)
}

func TestHandlerNilGuardBypassesCheck(t *testing.T) {
	obsv := observability.NewNoopExporters()
	stopper := &fakeSandboxStopper{}
	handler := Handler(obsv, stopper, nil)

	ctx := newCtx()
	payload := marshalJob(ctx, t, "compute-1", 42, 1)

	rr := aqueduct.ReceiveResult{
		Job: aqueduct.Job{
			ID:      "job-1",
			Queue:   jobs.StopAgentComputeJobQueueName,
			Payload: payload,
		},
	}

	_, err := handler(ctx, rr)
	require.NoError(t, err)
	require.Len(t, stopper.calls, 1)
	assert.Equal(t, "compute-1", stopper.calls[0].computeID)
	assert.Equal(t, uint64(42), stopper.calls[0].actorID)
}

func TestHandlerSuccessfulStop(t *testing.T) {
	obsv := observability.NewNoopExporters()
	stopper := &fakeSandboxStopper{}
	guard := &fakeGuard{
		isCurrentFn: func(string, int64) bool { return true },
	}
	handler := Handler(obsv, stopper, guard)

	ctx := newCtx()
	payload := marshalJob(ctx, t, "compute-xyz", 99, 3)

	rr := aqueduct.ReceiveResult{
		Job: aqueduct.Job{
			ID:      "job-1",
			Queue:   jobs.StopAgentComputeJobQueueName,
			Payload: payload,
		},
	}

	_, err := handler(ctx, rr)
	require.NoError(t, err)
	require.Len(t, stopper.calls, 1)
	assert.Equal(t, "compute-xyz", stopper.calls[0].computeID)
	assert.Equal(t, uint64(99), stopper.calls[0].actorID)
}

func TestHandlerStopFailurePropagates(t *testing.T) {
	obsv := observability.NewNoopExporters()
	stopErr := goerrors.New("boom")
	stopper := &fakeSandboxStopper{
		stopFn: func(context.Context, string, uint64) error { return stopErr },
	}
	handler := Handler(obsv, stopper, &fakeGuard{})

	ctx := newCtx()
	payload := marshalJob(ctx, t, "compute-1", 1, 1)

	rr := aqueduct.ReceiveResult{
		Job: aqueduct.Job{
			ID:      "job-1",
			Queue:   jobs.StopAgentComputeJobQueueName,
			Payload: payload,
		},
	}

	_, err := handler(ctx, rr)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "failed to stop agent compute")
	assert.ErrorIs(t, err, stopErr)
}
