package handlers

import (
	"context"
	"encoding/json"
	"testing"
	"time"

	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/stretchr/testify/assert"
	"golang.org/x/sync/errgroup"
)

func Test_ProcessMessageWithoutRateLimit(t *testing.T) {
	// Create a new RollupHandler
	rh := NewRollupHandler(
		&HandlerParams{
			statter: stats.NullStatter,
		},
		doTestRollup,
		models.WorkerTypeCustomerAzureEmissionDailyRollup,
		"testRollup")
	// Process message
	err := rh.ProcessMessage(context.Background(), log.NewNullLogger(), aqueduct.ReceiveResult{
		Job: aqueduct.Job{
			Payload: func() []byte {
				i := models.Item{
					Key: models.Key{
						PartitionKey: "123:actions_storage:2240:2",
						Id:           "123:actions_storage:2240:2",
					},
					UsageAt: *models.NewUsageTimeFromTime(time.Date(1970, time.January, 1, 0, 0, 0, 0, time.UTC)),
				}
				p, _ := json.Marshal(&i)
				return p
			}(),
		},
		ValidPayload: true,
	})
	assert.Nil(t, err)
}

func Test_ProcessMessageRateLimit(t *testing.T) {
	// Create a new RollupHandler
	rh := NewRollupHandler(
		&HandlerParams{
			statter: stats.NullStatter,
		},
		doTestRollup,
		models.WorkerTypeCustomerAzureEmissionDailyRollup,
		"testRollup",
		// Setting a limit of 1000 here means it'll process 100 messages (below in the loop) in ~0.1s
		WithRateLimit(1000))

	// Process message
	// create a loop of 100 messages to process
	for i := 0; i < 100; i++ {
		err := rh.ProcessMessage(context.Background(), log.NewNullLogger(), aqueduct.ReceiveResult{
			Job: aqueduct.Job{
				Payload: func() []byte {
					i := models.Item{
						Key: models.Key{
							PartitionKey: "123:actions_storage:2240:2",
							Id:           "123:actions_storage:2240:2",
						},
						UsageAt: *models.NewUsageTimeFromTime(time.Date(1970, time.January, 1, 0, 0, 0, 0, time.UTC)),
					}
					p, _ := json.Marshal(&i)
					return p
				}(),
			},
			ValidPayload: true,
		})
		assert.Nil(t, err)
	}
}

func doTestRollup(ctx context.Context, logger log.Logger, item models.Item, group *errgroup.Group, handler *RollupHandler) error {
	return nil
}
