package o11y

import (
	"context"
	"testing"

	"github.com/stretchr/testify/require"
)

var _ HydroRequestInfo = &dummyRequestInfo{}

type dummyRequestInfo struct{}

func (r *dummyRequestInfo) HydroOffset(context.Context) int64    { return 1 }
func (r *dummyRequestInfo) HydroPartition(context.Context) int64 { return 2 }
func (r *dummyRequestInfo) HydroTopic(context.Context) string    { return "test.Topic" }

type dummyAqueductWorkerConfig struct{}

func (wg dummyAqueductWorkerConfig) GetApp() string       { return "app_name" }
func (wg dummyAqueductWorkerConfig) GetQueue() string     { return "queue_name" }
func (wg dummyAqueductWorkerConfig) GetParallelJobs() int { return 1 }

func Test_CtxControl(t *testing.T) {
	r := require.New(t)

	t.Run("on a ctx with aqueduct info", func(t *testing.T) {
		workerConfig := dummyAqueductWorkerConfig{}

		ctx := CtxSetAqueductInfo(context.Background(), workerConfig)

		r.Equal("queue_name", CtxGetAqueductQueue(ctx))
		r.Equal("app_name", CtxGetAqueductApp(ctx))
		r.Equal("1", CtxGetAqueductParallelJobs(ctx))
	})

	t.Run("on a ctx with hydro info", func(t *testing.T) {
		ctx := CtxSetHydroInfo(context.Background(), "test", &dummyRequestInfo{})

		r.Equal("test", CtxGetHydroConsumer(ctx))
		r.Equal("1", CtxGetHydroOffset(ctx))
		r.Equal("test.Topic", CtxGetHydroTopic(ctx))
		r.Equal("2", CtxGetHydroPartition(ctx))
	})

	t.Run("on a context without hydro info", func(t *testing.T) {
		ctx := context.Background()

		r.Empty(CtxGetHydroConsumer(ctx))
		r.Empty(CtxGetHydroOffset(ctx))
		r.Empty(CtxGetHydroTopic(ctx))
		r.Empty(CtxGetHydroPartition(ctx))
	})

	t.Run("on a ctx with request ID", func(t *testing.T) {
		ctx := CtxSetRequestID(context.Background())

		r.NotEmpty(CtxGetRequestID(ctx))
	})

	t.Run("on a ctx without requestID", func(t *testing.T) {
		ctx := context.Background()

		r.Empty(CtxGetRequestID(ctx))
	})

	t.Run("on a ctx with notification ID", func(t *testing.T) {
		ctx := CtxSetNotificationID(context.Background(), "some/notification#123")

		r.Equal("some/notification#123", CtxGetNotificationID(ctx))
	})

	t.Run("on a ctx without notification ID", func(t *testing.T) {
		ctx := context.Background()

		r.Empty(CtxGetNotificationID(ctx))
	})

	t.Run("on a ctx with actor ID", func(t *testing.T) {
		ctx := CtxSetActorID(context.Background(), int64(1))

		r.Equal(int64(1), CtxGetActorID(ctx))
	})

	t.Run("on a ctx with subject type", func(t *testing.T) {
		ctx := CtxSetSubjectType(context.Background(), "issue")

		r.Equal("issue", CtxGetSubjectType(ctx))
	})

	t.Run("on a ctx with subject value", func(t *testing.T) {
		ctx := CtxSetSubjectValue(context.Background(), "123")

		r.Equal("123", CtxGetSubjectValue(ctx))
	})

	t.Run("on a ctx without actor ID", func(t *testing.T) {
		ctx := context.Background()

		r.Equal(int64(0), CtxGetActorID(ctx))
	})

	t.Run("on a ctx with user ID", func(t *testing.T) {
		ctx := CtxSetUserID(context.Background(), int64(1))

		r.Equal(int64(1), CtxGetUserID(ctx))
	})

	t.Run("on a ctx without user ID", func(t *testing.T) {
		ctx := context.Background()

		r.Equal(int64(0), CtxGetUserID(ctx))
	})

	t.Run("on a ctx with process info", func(t *testing.T) {
		ctx := CtxSetProcessInfo(context.Background(), "test", "test-unit")

		r.Equal("test", CtxGetDeploymentEnv(ctx))
		r.Equal("test-unit", CtxGetUnit(ctx))
	})

	t.Run("on a ctx without process info", func(t *testing.T) {
		ctx := context.Background()

		r.Empty(CtxGetDeploymentEnv(ctx))
		r.Empty(CtxGetUnit(ctx))
	})
}
