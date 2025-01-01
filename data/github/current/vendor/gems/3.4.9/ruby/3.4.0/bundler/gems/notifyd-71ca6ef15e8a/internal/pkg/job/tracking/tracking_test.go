package tracking

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/github/github-telemetry-go/log"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/proto"

	schemav0 "github.com/github/notifyd/hydro/schemas/notifyd/v0"
	job "github.com/github/notifyd/internal/pkg/job/testhelper"
	"github.com/github/notifyd/internal/pkg/tenancy"
)

func Test_JobTracker_Run(t *testing.T) {
	ctx := context.Background()
	msg := &schemav0.Notify{}

	filter := func(_ *schemav0.Notify) (bool, string) { return true, "" }
	scrub := func(_ *schemav0.Notify) error { return nil }
	publisher := NewPublisherMock(t)

	matcher := func(actual *schemav0.Notify) bool {
		return proto.Equal(msg, actual)
	}

	publisher.On("Publish", ctx, mock.MatchedBy(matcher)).Return(nil)

	tracker := NewJobTracker("test", publisher, filter, scrub)

	req, err := job.NewTinyRequest(time.Now(), msg)
	require.NoError(t, err)

	err = tracker.Run(ctx, tenancy.NewSingleTenant(), log.NewNullLogger(), req)
	require.NoError(t, err)
}

func Test_JobTracker_Run_Filter(t *testing.T) {
	ctx := context.Background()
	msg := &schemav0.Notify{}

	filter := func(_ *schemav0.Notify) (bool, string) { return false, "do not publish" }
	scrub := func(_ *schemav0.Notify) error { return nil }
	publisher := NewPublisherMock(t)

	tracker := NewJobTracker("test", publisher, filter, scrub)

	req, err := job.NewTinyRequest(time.Now(), msg)
	require.NoError(t, err)

	err = tracker.Run(ctx, tenancy.NewSingleTenant(), log.NewNullLogger(), req)
	require.NoError(t, err)

	// No expectation in the publisher, if is called this fails
	publisher.AssertExpectations(t)
}

func Test_JobTracker_Run_Scrub(t *testing.T) {
	ctx := context.Background()
	msg := &schemav0.Notify{
		NotificationId: "notification-id",
		Actor:          &schemav0.Notify_Actor{Id: 1},
	}

	filter := func(_ *schemav0.Notify) (bool, string) { return true, "" }
	scrubID := func(msg *schemav0.Notify) error {
		msg.NotificationId = "scrubbed-id"
		return nil
	}
	scrubActor := func(msg *schemav0.Notify) error {
		msg.Actor.Id = 100
		return nil
	}
	publisher := NewPublisherMock(t)

	// The published message is the scrubbed one
	matcher := func(msg *schemav0.Notify) bool {
		return msg.NotificationId == "scrubbed-id" && msg.Actor.Id == 100
	}
	publisher.On("Publish", ctx, mock.MatchedBy(matcher)).Return(nil)

	tracker := NewJobTracker("test", publisher, filter, scrubID, scrubActor)

	req, err := job.NewTinyRequest(time.Now(), msg)
	require.NoError(t, err)

	err = tracker.Run(ctx, tenancy.NewSingleTenant(), log.NewNullLogger(), req)
	require.NoError(t, err)

	publisher.AssertExpectations(t)
}

func Test_JobTracker_Run_ScrubError(t *testing.T) {
	ctx := context.Background()
	msg := &schemav0.Notify{
		NotificationId: "notification-id",
	}

	filter := func(_ *schemav0.Notify) (bool, string) { return true, "" }
	scrub := func(msg *schemav0.Notify) error { return errors.New("failed to scrub") }
	publisher := NewPublisherMock(t)

	tracker := NewJobTracker("test", publisher, filter, scrub)

	req, err := job.NewTinyRequest(time.Now(), msg)
	require.NoError(t, err)

	err = tracker.Run(ctx, tenancy.NewSingleTenant(), log.NewNullLogger(), req)
	require.Error(t, err)
	require.Equal(t, "failed to scrub", err.Error())

	publisher.AssertExpectations(t)
}

func Test_JobTracker_Run_CancelledContext(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	msg := &schemav0.Notify{
		NotificationId: "notification-id",
	}

	filter := func(_ *schemav0.Notify) (bool, string) { return true, "" }
	scrub := func(msg *schemav0.Notify) error { return nil }
	publisher := NewPublisherMock(t)

	tracker := NewJobTracker("test", publisher, filter, scrub)

	req, err := job.NewTinyRequest(time.Now(), msg)
	require.NoError(t, err)

	cancel() // cancel context
	err = tracker.Run(ctx, tenancy.NewSingleTenant(), log.NewNullLogger(), req)
	require.Error(t, err)
	require.Equal(t, ctx.Err(), err)

	publisher.AssertExpectations(t)
}
