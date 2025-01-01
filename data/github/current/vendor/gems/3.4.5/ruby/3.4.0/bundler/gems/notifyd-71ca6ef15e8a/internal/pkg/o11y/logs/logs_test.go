package logs

import (
	"context"
	"testing"

	"github.com/benbjohnson/clock"
	"github.com/stretchr/testify/require"

	"github.com/github/github-telemetry-go/kvp"
	ghhydro "github.com/github/hydro-client-go/v7/pkg/hydro"

	"github.com/github/notifyd/internal/pkg/hydro"
	"github.com/github/notifyd/internal/pkg/o11y"
)

type dummyAqueductWorkerConfig struct{}

func (wg dummyAqueductWorkerConfig) GetApp() string       { return "app_name" }
func (wg dummyAqueductWorkerConfig) GetQueue() string     { return "queue_name" }
func (wg dummyAqueductWorkerConfig) GetParallelJobs() int { return 1 }

func Test_Prepare_Integration(t *testing.T) {
	r := require.New(t)
	allKeys := []string{
		"gh.request_id",
		"messaging.client_id",
		"messaging.message.offset",
		"messaging.message.partition",
		"messaging.message.topic",
		"gh.notifyd.notification.id",
		"gh.actor.id",
		"gh.user.id",
		"gh.aqueduct.queue.name",
		"gh.aqueduct.app",
		"gh.notifyd.aqueduct.parallel_jobs",
		"gh.notifications.subject.type",
		"gh.notifications.subject.id",
		"code.namespace",
		"code.function",
		"gh.tenant",
	}

	setup := func() context.Context {
		return o11y.CtxSetProcessInfo(context.Background(), "test", "test")
	}

	testCases := []struct {
		name  string
		setup func() context.Context
		keys  []string
	}{
		{
			name:  "with an empty context",
			setup: setup,
			keys:  []string{},
		},
		{
			name:  "with a request_id",
			setup: func() context.Context { return o11y.CtxSetRequestID(setup()) },
			keys:  []string{"gh.request_id"},
		},
		{
			name: "with hydro info",
			setup: func() context.Context {
				msg := ghhydro.Message{
					Offset: int64(1),
					Topic:  "test.Topic",
				}
				return o11y.CtxSetHydroInfo(setup(), "test", hydro.NewRequest(msg, clock.NewMock()))
			},
			keys: []string{"messaging.client_id", "messaging.message.offset", "messaging.message.topic", "messaging.message.partition"},
		},
		{
			name: "with aqueduct info",
			setup: func() context.Context {
				return o11y.CtxSetAqueductInfo(setup(), dummyAqueductWorkerConfig{})
			},

			keys: []string{"gh.notifyd.aqueduct.parallel_jobs", "gh.aqueduct.app", "gh.aqueduct.queue.name"},
		},
		{
			name:  "with a notification_id",
			setup: func() context.Context { return o11y.CtxSetNotificationID(setup(), "some_id") },
			keys:  []string{"gh.notifyd.notification.id"},
		},
		{
			name:  "with a list_id",
			setup: func() context.Context { return o11y.CtxSetListID(setup(), "some_id") },
			keys:  []string{"gh.notifications.list.id"},
		},
		{
			name:  "with a list_type",
			setup: func() context.Context { return o11y.CtxSetListType(setup(), "some_type") },
			keys:  []string{"gh.notifications.list.type"},
		},
		{
			name:  "with a thread_id",
			setup: func() context.Context { return o11y.CtxSetThreadID(setup(), "some_id") },
			keys:  []string{"gh.notifications.thread.id"},
		},
		{
			name:  "with a thread_type",
			setup: func() context.Context { return o11y.CtxSetThreadType(setup(), "some_type") },
			keys:  []string{"gh.notifications.thread.type"},
		},
		{
			name:  "with a comment_id",
			setup: func() context.Context { return o11y.CtxSetCommentID(setup(), "some_id") },
			keys:  []string{"gh.notifications.comment.id"},
		},
		{
			name:  "with a comment_type",
			setup: func() context.Context { return o11y.CtxSetCommentType(setup(), "some_type") },
			keys:  []string{"gh.notifications.comment.type"},
		},
		{
			name:  "with reasons",
			setup: func() context.Context { return o11y.CtxSetReasons(setup(), "some_reason") },
			keys:  []string{"gh.notifyd.reasons"},
		},
		{
			name:  "with a channel",
			setup: func() context.Context { return o11y.CtxSetChannel(setup(), "some_channel") },
			keys:  []string{"gh.notifyd.channel"},
		},
		{
			name:  "with subject type information",
			setup: func() context.Context { return o11y.CtxSetSubjectType(setup(), "subject_type_info") },
			keys:  []string{"gh.notifications.subject.type"},
		},
		{
			name:  "with subject value information",
			setup: func() context.Context { return o11y.CtxSetSubjectValue(setup(), "subject_value_info") },
			keys:  []string{"gh.notifications.subject.id"},
		},
		{
			name:  "with a user_id",
			setup: func() context.Context { return o11y.CtxSetUserID(setup(), 1) },
			keys:  []string{"gh.user.id"},
		},
		{
			name:  "with a actor_id",
			setup: func() context.Context { return o11y.CtxSetActorID(setup(), 1) },
			keys:  []string{"gh.actor.id"},
		},
		{
			name: "with everything",
			setup: func() context.Context {
				msg := ghhydro.Message{
					Offset:    int64(1),
					Topic:     "test.Topic",
					Partition: 2,
				}
				ctx := o11y.CtxSetHydroInfo(setup(), "test", hydro.NewRequest(msg, clock.NewMock()))
				ctx = o11y.CtxSetRequestID(ctx)
				ctx = o11y.CtxSetActorID(ctx, 1)
				ctx = o11y.CtxSetUserID(ctx, 1)
				ctx = o11y.CtxSetNotificationID(ctx, "some_id")
				ctx = o11y.CtxSetSubjectType(ctx, "subject_type_info")
				ctx = o11y.CtxSetSubjectValue(ctx, "subject_value_info")
				ctx = o11y.CtxSetAqueductInfo(ctx, dummyAqueductWorkerConfig{})
				ctx = o11y.CtxSetPackage(ctx, "some-package")
				ctx = o11y.CtxSetMethod(ctx, "some-method")
				ctx = o11y.CtxSetTenantSlug(ctx, "some-tenant")
				return ctx
			},
			keys: allKeys,
		},
	}

	for _, test := range testCases {
		assertCtxFields := func(fields []kvp.Field) {
			keys := make([]string, len(fields))
			for i, field := range fields {
				keys[i] = field.Key
			}

			r.Contains(keys, "gh.notifyd.unit.name", "it always has a gh.notifyd.unit.name")
			r.Contains(keys, "deployment.environment", "it always has an deployment.environment")
			for _, key := range allKeys {
				if has(t, test.keys, key) {
					r.Contains(keys, key)
				} else {
					r.NotContains(keys, key)
				}
			}
		}

		t.Run(test.name, func(t *testing.T) {
			ctx := test.setup()
			assertCtxFields(CtxFields(ctx))
		})
	}
}

func has(t *testing.T, ary []string, el string) bool {
	t.Helper()
	for _, e := range ary {
		if e == el {
			return true
		}
	}

	return false
}
