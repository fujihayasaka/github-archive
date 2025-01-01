package notify

import (
	"github.com/github/notifyd/internal/pkg/notify/stages"
)

// NotificationService represents the service that handles the notification pipeline.
type NotificationService struct {
	// calculateRecipients uses explicit recipients and the subscription system to qualify any
	// possible user as a recipient of notifications.
	stages.ICalculateRecipientsStage

	// authorizeRecipients takes the qualified recipients and makes sure that they are allowed to
	// receive the notifications based on the subject and their permissions.
	authorizeRecipients stages.IAuthorizeRecipientsStage

	// validateDotcomRecipientPolicies uses a callback to the monolith in order to ensure some checks
	// are done, like spaminess, or ignored users.
	validateDotcomRecipientPolicies stages.IValidateDotcomRecipientPoliciesStage

	// routeRecipientsToChannels makes sure that we use our settings in order to deliver the
	// notifications in the correct channel(s) selected by each user.
	routeRecipientsToChannels stages.IRouteRecipientsToChannelsStage

	// scheduleEmailNotifications publishes the email notifications so that the next step in the
	// pipeline handles them.
	scheduleEmailNotifications stages.NotificationsScheduler

	// schedulePushNotifications publishes the push notifications so that the next step in the
	// pipeline handles them.
	schedulePushNotifications stages.NotificationsScheduler

	// scheduleWebNotifications publishes the web notifications so that the next step in the
	// pipeline handles them.
	scheduleWebNotifications stages.NotificationsScheduler

	stages.IRouteRecipientsStage

	stages.IQueueBatchedRecipientsStage
}

// NewNotificationService creates a new NotificationService.
func NewNotificationService(
	calculateRecipients stages.ICalculateRecipientsStage,
	authorizeRecipients stages.IAuthorizeRecipientsStage,
	validateDotcomRecipientPolicies stages.IValidateDotcomRecipientPoliciesStage,
	routeRecipientsToChannels stages.IRouteRecipientsToChannelsStage,
	scheduleEmailNotifications,
	schedulePushNotifications,
	scheduleWebNotifications stages.NotificationsScheduler,
	routeRecipientsStage stages.IRouteRecipientsStage,
	queueBatchedRecipientsStage stages.IQueueBatchedRecipientsStage) *NotificationService {
	return &NotificationService{
		ICalculateRecipientsStage:       calculateRecipients,
		authorizeRecipients:             authorizeRecipients,
		validateDotcomRecipientPolicies: validateDotcomRecipientPolicies,
		routeRecipientsToChannels:       routeRecipientsToChannels,
		scheduleEmailNotifications:      scheduleEmailNotifications,
		schedulePushNotifications:       schedulePushNotifications,
		scheduleWebNotifications:        scheduleWebNotifications,
		IRouteRecipientsStage:           routeRecipientsStage,
		IQueueBatchedRecipientsStage:    queueBatchedRecipientsStage,
	}
}
