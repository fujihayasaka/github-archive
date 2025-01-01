// Package deliverytracking implements a tracker for delivered notifications.
package deliverytracking

import (
	"context"

	"github.com/github/hydro-client-go/v7/pkg/hydro"

	messages "github.com/github/notifyd/hydro/schemas/notifyd/v0"
	metricspkg "github.com/github/notifyd/internal/pkg/job/metrics"
	"github.com/github/notifyd/internal/pkg/o11y"
)

const topic = "notifyd.v0.DeliveredNotification"

// HydroTracker represents a hydro-backed publisher tracking delivered notifications.
type HydroTracker struct {
	*hydro.Publisher
	metrics *metricspkg.PublisherMetrics
}

// DeliveryTracker represents a tracker for delivered notifications.
type DeliveryTracker interface {
	Track(context.Context, *messages.DeliveredNotification) error
}

// NewHydroTracker returns a new HydroTracker.
func NewHydroTracker(publisher *hydro.Publisher, metrics *metricspkg.PublisherMetrics) *HydroTracker {
	return &HydroTracker{Publisher: publisher, metrics: metrics}
}

// Track tracks a delivered notification, publishing it to hydro.
func (t *HydroTracker) Track(ctx context.Context, m *messages.DeliveredNotification) error {
	ctx = o11y.CtxSetUserID(ctx, int64(m.GetUserId()))
	ctx = o11y.CtxSetNotificationID(ctx, m.GetNotificationId())

	err := t.Publish(m, hydro.WithTopic(topic))
	t.metrics.Send(ctx, "delivered_notification", err, metricspkg.WithHydroKey())

	return err
}

// Close closes the publisher.
func (t *HydroTracker) Close() {
	_ = t.Publisher.Close()
}
