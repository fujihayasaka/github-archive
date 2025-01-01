package clients

import (
	"context"

	clockpkg "github.com/benbjohnson/clock"
	ghstats "github.com/github/go-stats"

	"github.com/github/notifyd/internal/pkg/devicetokens"
)

// stats implements MobileClient in order to wrap any existing client with stats
type stats struct {
	client  MobileClient
	clock   clockpkg.Clock
	statter ghstats.Client
}

// NewStatsClient wraps an existing MobileClient with stats.
func NewStatsClient(client MobileClient, clock clockpkg.Clock, statter ghstats.Client) MobileClient {
	return stats{client: client, clock: clock, statter: statter}
}

// SendNotification sends a push notification to the given device tokens.
func (c stats) SendNotification(ctx context.Context, notification Notification, deviceTokens devicetokens.Tokens) (Response, error) {
	start := c.clock.Now()
	response, err := c.client.SendNotification(ctx, notification, deviceTokens)
	elapsed := c.clock.Since(start)

	c.statter.DistributionMs("push_notifications.time", tags(err), elapsed)
	c.statter.Counter("push_notifications.count", tags(err), 1)
	c.statter.Counter("push_notifications.tokens.count", ghstats.Tags{"status": "delivered"}, int64(response.DeliveredCount))
	c.statter.Counter("push_notifications.tokens.count", ghstats.Tags{"status": "failed"}, int64(response.FailedCount))

	return response, err
}

func tags(err error) ghstats.Tags {
	if err != nil {
		return ghstats.Tags{"status": "failed"}
	}

	return ghstats.Tags{"status": "success"}
}
