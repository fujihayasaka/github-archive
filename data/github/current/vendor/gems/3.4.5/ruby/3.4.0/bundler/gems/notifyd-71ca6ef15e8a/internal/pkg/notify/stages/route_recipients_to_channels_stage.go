package stages

import (
	"context"

	clockpkg "github.com/benbjohnson/clock"
	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/go-stats"

	"github.com/github/notifyd/internal/pkg/notify"
	"github.com/github/notifyd/internal/pkg/o11y/tracing"
	"github.com/github/notifyd/internal/pkg/routing"
)

type routeRecipientsToChannelsStage struct {
	routingService routing.Service
	clock          clockpkg.Clock
	telem          *telemetry.Provider
	statter        stats.Client
}

// NewRouteRecipientsToChannelsStage creates a new route recipients to channels stage.
func NewRouteRecipientsToChannelsStage(routingService routing.Service, clock clockpkg.Clock, telem *telemetry.Provider, statter stats.Client) IRouteRecipientsToChannelsStage {
	return &routeRecipientsToChannelsStage{
		routingService: routingService,
		clock:          clock,
		telem:          telem,
		statter:        statter,
	}
}

// RouteRecipientsToChannels routes recipients to channels.
func (s *routeRecipientsToChannelsStage) RouteRecipientsToChannels(ctx context.Context, recipients notify.RecipientIDToReasons, msg *notify.Notification) notify.RecipientToDeliveryMetadata {
	ctx, span := tracing.StartSpanWithCaller(ctx)
	defer span.End()

	start := s.clock.Now()
	defer func() {
		s.statter.DistributionMs(statsTimingKey, stats.Tags{"stage": "route_recipients_to_channel"}, s.clock.Since(start))
	}()

	event := routing.NewMatchQuery(msg.ID, msg.ActorID, msg.MessageMatchFields, msg.ReasonGroups())

	return s.routingService.GetDeliveryMetadata(ctx, recipients, event)
}
