package deliverytracking

import (
	"context"
	"testing"

	"github.com/github/go-stats"
	ghhydro "github.com/github/hydro-client-go/v7/pkg/hydro"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/proto"

	messages "github.com/github/notifyd/hydro/schemas/notifyd/v0"
	"github.com/github/notifyd/internal/pkg/hydro"
	"github.com/github/notifyd/internal/pkg/job/metrics"
	"github.com/github/notifyd/internal/pkg/o11y/logs"
)

func TestTrack(t *testing.T) {
	r := require.New(t)
	ctx := context.Background()

	publisherChan := make(chan ghhydro.Message, 1)
	publisher, _ := hydro.BuildMemoryPublisher(publisherChan)

	m := metrics.NewPublisherMetrics(logs.NullTelem, stats.NullStatter)
	deliveryTracker := HydroTracker{Publisher: publisher, metrics: m}
	message := messages.DeliveredNotification{NotificationId: "notification-id"}

	err := deliveryTracker.Track(ctx, &message)
	r.NoError(err)

	var hydroPublishedMessage messages.DeliveredNotification
	err = hydro.UnmarshalMessage(<-publisherChan, &hydroPublishedMessage)
	r.NoError(err)
	r.True(proto.Equal(&hydroPublishedMessage, &message))
}
