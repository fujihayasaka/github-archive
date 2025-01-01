package metrics

import (
	"context"
	"errors"
	"testing"

	"github.com/github/go-stats"
	stats_mock "github.com/github/go-stats/mocks"

	"github.com/github/notifyd/internal/pkg/o11y/logs"
)

func Test_PublishMetrics_Send(t *testing.T) {
	ctx := context.Background()

	statsMock := new(stats_mock.Client)
	statsMock.On("Counter", "hydro.publish", stats.Tags{"status": "succeeded", "message_type": "test"}, int64(1))

	publisher := NewPublisherMetrics(logs.NullTelem, statsMock)
	publisher.Send(ctx, "test", nil)
}

func Test_PublishMetrics_Send_OnError(t *testing.T) {
	ctx := context.Background()

	statsMock := new(stats_mock.Client)
	statsMock.On("Counter", "hydro.publish", stats.Tags{"status": "failed", "message_type": "test"}, int64(1))

	publisher := NewPublisherMetrics(logs.NullTelem, statsMock)
	publisher.Send(ctx, "test", errors.New("test"))
}

func Test_PublishMetrics_Send_WithHydroKey(t *testing.T) {
	ctx := context.Background()

	statsMock := new(stats_mock.Client)
	statsMock.On("Counter", "hydro.publish", stats.Tags{"status": "succeeded", "message_type": "test"}, int64(1))

	publisher := NewPublisherMetrics(logs.NullTelem, statsMock)
	publisher.Send(ctx, "test", nil, WithHydroKey())
}

func Test_PublishMetrics_Send_WithAqueductKey(t *testing.T) {
	ctx := context.Background()

	statsMock := new(stats_mock.Client)
	statsMock.On("Counter", "aqueduct.publish", stats.Tags{"status": "succeeded", "message_type": "test"}, int64(1))

	publisher := NewPublisherMetrics(logs.NullTelem, statsMock)
	publisher.Send(ctx, "test", nil, WithAqueductKey())
}
