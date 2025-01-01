package stages

import (
	"context"
	"sort"
	"testing"

	"github.com/benbjohnson/clock"
	"github.com/stretchr/testify/require"

	ghaqueduct "github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/go-stats"

	"github.com/github/notifyd/internal/pkg/aqueduct"
	"github.com/github/notifyd/internal/pkg/compress"
	"github.com/github/notifyd/internal/pkg/notify"
	"github.com/github/notifyd/internal/pkg/o11y/logs"

	schema_pb "github.com/github/notifyd/hydro/schemas/notifyd/v0"
	"github.com/github/notifyd/internal/pkg/hydro"
	"github.com/github/notifyd/internal/pkg/tenancy"
)

func TestQueueBatchedRecipientsStage_Execute(t *testing.T) {
	r := require.New(t)

	inflate := func(job *ghaqueduct.Job) ([]byte, error) {
		encoding := job.Headers["content-encoding"]
		if encoding == "" {
			return job.Payload, nil
		}

		return compress.Decompress(compress.Encoding(encoding), job.Payload)
	}

	batchesChannel := make(chan ghaqueduct.Job, 3)
	senderForBatches, _ := aqueduct.BuildMemorySender(batchesChannel)

	batchQueuePublisher := &BatchQueuePublisher{client: senderForBatches, app: "notifyd-test", telem: logs.NullTelem}

	stage := NewQueueBatchedRecipientsStage(batchQueuePublisher, clock.NewMock(), logs.NullTelem, stats.NullStatter)

	ctx := context.Background()
	notifyMessage := &schema_pb.Notify{
		Actor:          &schema_pb.Notify_Actor{Id: 1},
		NotificationId: "test-notification-id",
	}

	recipients := make(notify.RecipientIDToReasons)
	for i := 1; i <= 3; i++ {
		recipients[int64(i)] = []string{"subscribed", "mention"}
	}

	stage.QueueBatchedRecipients(ctx, tenancy.NewSingleTenant(), recipients, notifyMessage, notify.Batcher{Size: 1})

	var receivedBatchDeliveries []*schema_pb.Notify
	close(batchesChannel)
	for job := range batchesChannel {
		r.Equal(aqueduct.QueueNotify, job.Queue)
		payload, err := inflate(&job)
		r.NoError(err, "error inflating hydro message")
		receivedBatchDelivery := new(schema_pb.Notify)
		err = hydro.UnmarshalBytes(payload, receivedBatchDelivery)
		r.NoError(err, "error unmarshaling hydro message")
		receivedBatchDeliveries = append(receivedBatchDeliveries, receivedBatchDelivery)
	}
	r.Len(receivedBatchDeliveries, 3)

	sort.Slice(receivedBatchDeliveries, func(i, j int) bool {
		return len(receivedBatchDeliveries[i].ExplicitRecipients[0].UserIds) > len(receivedBatchDeliveries[j].ExplicitRecipients[0].UserIds)
	})

	for _, message := range receivedBatchDeliveries {
		// notify_subscribers flag is set to false
		r.False(message.FeatureSwiches["notify_subscribers"])
		validateReasonCounts(t, message, 1)
	}
}

func validateReasonCounts(t *testing.T, message *schema_pb.Notify, count int) {
	t.Helper()
	for _, recipientsToReason := range message.ExplicitRecipients {
		switch reason := recipientsToReason.Reason; reason {
		case "subscribed":
			require.Len(t, recipientsToReason.UserIds, count)
		case "mention":
			require.Len(t, recipientsToReason.UserIds, count)
		default:
			require.Fail(t, "reason not expected")
		}
	}
}
