package mobile

import (
	"context"
	"testing"
	"time"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/go-stats"
	hydropkg "github.com/github/hydro-client-go/v7/pkg/hydro"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/reflect/protoreflect"
	"google.golang.org/protobuf/types/known/anypb"

	schemav0 "github.com/github/notifyd/hydro/schemas/notifyd/v0"
	"github.com/github/notifyd/hydro/schemas/notifyd/v0/entities"
	"github.com/github/notifyd/internal/pkg/hydro"
	job "github.com/github/notifyd/internal/pkg/job/testhelper"
	"github.com/github/notifyd/internal/pkg/tenancy"
	"github.com/github/notifyd/proto/layouts/mobile"
)

func Test_TrackerRun(t *testing.T) {
	ctx := context.Background()

	logger := log.NewNullLogger()
	telem := &telemetry.Provider{Logger: logger}
	statter := stats.NullStatter

	publisherChan := make(chan hydropkg.Message, 1)
	defer close(publisherChan)
	publisher, err := hydro.BuildMemoryPublisher(publisherChan)
	require.NoError(t, err)

	layout := getLayout(t)
	msg := &schemav0.DeliverMobilePush{
		LayoutData: layout,
	}
	req, err := job.NewTinyRequest(time.Now(), msg)
	require.NoError(t, err)

	tracker := NewTracker(telem, statter, publisher)

	err = tracker.Run(ctx, tenancy.NewSingleTenant(), logger, req)
	require.NoError(t, err)

	var hydroPublishedMessage schemav0.DeliverMobilePush
	err = hydro.UnmarshalMessage(<-publisherChan, &hydroPublishedMessage)
	require.NoError(t, err)

	require.Contains(t, hydroPublishedMessage.LayoutData.GetTypeUrl(), "notifyd.v0.entities.LayoutSummary")
}

func Test_TrackerRun_WithRetries(t *testing.T) {
	ctx := context.Background()

	logger := log.NewNullLogger()
	telem := &telemetry.Provider{Logger: logger}
	statter := stats.NullStatter

	publisherChan := make(chan hydropkg.Message, 1)
	defer close(publisherChan)
	publisher, err := hydro.BuildMemoryPublisher(publisherChan)
	require.NoError(t, err)

	msg := &schemav0.DeliverMobilePush{
		Retries: &entities.Retries{Attempts: 1},
	}
	req, err := job.NewTinyRequest(time.Now(), msg)
	require.NoError(t, err)

	tracker := NewTracker(telem, statter, publisher)

	err = tracker.Run(ctx, tenancy.NewSingleTenant(), logger, req)
	require.NoError(t, err)

	require.Empty(t, publisherChan, "failure: the message was published into the tracking topic")
}

func Test_scrubLayoutData(t *testing.T) {
	msg := &schemav0.DeliverMobilePush{
		LayoutData: getLayout(t),
	}

	err := scrubLayoutData(msg)
	require.NoError(t, err)

	layout := msg.GetLayoutData()
	require.NotNil(t, layout)

	require.Equal(t, "type.googleapis.com/hydro.schemas.notifyd.v0.entities.LayoutSummary", layout.GetTypeUrl())
	var mobileLayout entities.LayoutSummary
	err = proto.Unmarshal(layout.GetValue(), &mobileLayout)
	require.NoError(t, err)
	require.Equal(t, "type.googleapis.com/notifyd.layouts.mobile.Basic", mobileLayout.GetKind())
}

func asAny(t *testing.T, pb protoreflect.ProtoMessage) *anypb.Any {
	t.Helper()

	wrapped, err := anypb.New(pb)
	require.NoError(t, err)

	return wrapped
}

func getLayout(t *testing.T) *anypb.Any {
	t.Helper()

	basic := &mobile.Basic{
		Body: "this is a test",
	}

	return asAny(t, basic)
}
