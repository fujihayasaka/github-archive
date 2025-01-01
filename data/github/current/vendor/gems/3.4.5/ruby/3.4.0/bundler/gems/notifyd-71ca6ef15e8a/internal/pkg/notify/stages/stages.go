// Package stages implements the pipeline stages for processing notifications.
package stages

import (
	"context"

	schema_pb "github.com/github/notifyd/hydro/schemas/notifyd/v0"
	"github.com/github/notifyd/internal/pkg/notify"
	"github.com/github/notifyd/internal/pkg/tenancy"
)

const (
	// statsTimingKey measures how much time each stage takes
	statsTimingKey = "notifyd.notify.stages.time"
	// statsScheduleErrorsKey measures how many errors happened while scheduling deliveries on each
	// stage.
	statsScheduleErrorsKey = "notify.stages.schedule.errors"

	// statsDelivery measures how many events are through each one of the steps of the delivery
	// journey
	statsDelivery = "delivery"
)

// ICalculateRecipientsStage represents the stage that calculates the recipients.
type ICalculateRecipientsStage interface {
	AddSubscribers(ctx context.Context, recipients notify.RecipientIDToReasons, msg *notify.Notification) error
}

// IAuthorizeRecipientsStage represents the stage that authorizes the recipients.
type IAuthorizeRecipientsStage interface {
	AuthorizeRecipients(ctx context.Context, tenant tenancy.Tenant, recipientIDsToReasons notify.RecipientIDToReasons, msg *notify.Notification) (notify.RecipientIDToReasons, error)
}

// IValidateDotcomRecipientPoliciesStage represents the stage that validates the recipients against dotcom policies.
type IValidateDotcomRecipientPoliciesStage interface {
	ValidateDotcomPolicies(ctx context.Context, tenant tenancy.Tenant, recipientIDsToReasons notify.RecipientIDToReasons, msg *notify.Notification) (notify.RecipientIDToReasons, error)
	ValidateIgnoredRepository(ctx context.Context, tenant tenancy.Tenant, recipientIDsToReasons notify.RecipientIDToReasons, msg *notify.Notification) (notify.RecipientIDToReasons, error)
}

// IRouteRecipientsStage represents the stage that routes the recipients.
type IRouteRecipientsStage interface {
	RouteRecipients(ctx context.Context, tenant tenancy.Tenant, recipientIDsToReasons notify.RecipientIDToReasons, msg *notify.Notification) error
}

// IRouteRecipientsToChannelsStage represents the stage that routes the recipients to channels.
type IRouteRecipientsToChannelsStage interface {
	RouteRecipientsToChannels(ctx context.Context, potentialRecipientsIDToReasons notify.RecipientIDToReasons, msg *notify.Notification) notify.RecipientToDeliveryMetadata
}

// NotificationsScheduler represents the stage that schedules the notifications.
type NotificationsScheduler interface {
	ScheduleNotifications(ctx context.Context, tenant tenancy.Tenant, recipients notify.RecipientToDeliveryMetadata, msg *notify.Notification) error
}

// IQueueBatchedRecipientsStage represents the stage that queues the recipients.
type IQueueBatchedRecipientsStage interface {
	QueueBatchedRecipients(ctx context.Context, tenant tenancy.Tenant, recipientToDeliveryMetadata notify.RecipientIDToReasons, msg *schema_pb.Notify, batcher notify.Batcher)
}
