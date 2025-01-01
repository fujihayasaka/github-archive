package stages

import (
	"context"
	"testing"

	"github.com/benbjohnson/clock"
	"github.com/github/go-stats"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"

	schema_pb "github.com/github/notifyd/hydro/schemas/notifyd/v0"
	"github.com/github/notifyd/internal/pkg/featureflags"
	"github.com/github/notifyd/internal/pkg/notify"
	"github.com/github/notifyd/internal/pkg/o11y/logs"
	"github.com/github/notifyd/internal/pkg/subscriptions"
)

func Test_Execute(t *testing.T) {
	r := require.New(t)

	tests := []struct {
		name                              string
		notifyMessage                     *schema_pb.Notify
		subscriptionRecipientIDs          []int32
		subscriptionRecipientIDsToReasons notify.RecipientIDToReasons
		expectedMatchFields               notify.MessageMatchFields
		expectedRecipientIDsToReasons     notify.RecipientIDToReasons
		useNewSubscriptions               bool
		enabledRecipients                 map[string]bool
		err                               bool
	}{
		{
			name: "Returns only explicit recipients when related topics are missing",
			notifyMessage: &schema_pb.Notify{
				Actor:          &schema_pb.Notify_Actor{Id: 1},
				NotificationId: "test-notification-id",
				Context: &schema_pb.Notify_Context{
					Trigger: "create",
				},
				ExplicitRecipients: []*schema_pb.Notify_RecipientGroup{
					{Reason: "mention", UserIds: []int32{2}},
				},
				Subject: &schema_pb.Notify_Subject{Type: "Issue", Value: "1"},
			},
			expectedRecipientIDsToReasons: notify.RecipientIDToReasons{
				2: []string{"mention"},
			},
			useNewSubscriptions: true,
			err:                 true,
		},
		{
			name: "Returns only explicit recipients when subject is missing",
			notifyMessage: &schema_pb.Notify{
				Actor:          &schema_pb.Notify_Actor{Id: 1},
				NotificationId: "test-notification-id",
				Context: &schema_pb.Notify_Context{
					Trigger: "create",
				},
				ExplicitRecipients: []*schema_pb.Notify_RecipientGroup{
					{Reason: "mention", UserIds: []int32{2}},
				},
				RelatedTopics: []*schema_pb.Notify_Topic{
					{Type: "repository", Value: "123"},
				},
			},
			expectedRecipientIDsToReasons: notify.RecipientIDToReasons{
				2: []string{"mention"},
			},
			useNewSubscriptions: true,
			err:                 true,
		},
		{
			name: "Returns only explicit recipients when subject type is missing",
			notifyMessage: &schema_pb.Notify{
				Actor:          &schema_pb.Notify_Actor{Id: 1},
				NotificationId: "test-notification-id",
				Context: &schema_pb.Notify_Context{
					Trigger: "create",
				},
				ExplicitRecipients: []*schema_pb.Notify_RecipientGroup{
					{Reason: "mention", UserIds: []int32{2}},
				},
				Subject: &schema_pb.Notify_Subject{Value: "1"},
				RelatedTopics: []*schema_pb.Notify_Topic{
					{Type: "repository", Value: "123"},
				},
			},
			expectedRecipientIDsToReasons: notify.RecipientIDToReasons{
				2: []string{"mention"},
			},
			useNewSubscriptions: true,
			err:                 true,
		},
		{
			name: "Returns only explicit recipients when trigger is missing",
			notifyMessage: &schema_pb.Notify{
				Actor:          &schema_pb.Notify_Actor{Id: 1},
				NotificationId: "test-notification-id",
				Context:        &schema_pb.Notify_Context{},
				ExplicitRecipients: []*schema_pb.Notify_RecipientGroup{
					{Reason: "mention", UserIds: []int32{2}},
				},
				Subject: &schema_pb.Notify_Subject{Type: "Issue", Value: "1"},
				RelatedTopics: []*schema_pb.Notify_Topic{
					{Type: "repository", Value: "123"},
				},
			},
			expectedRecipientIDsToReasons: notify.RecipientIDToReasons{
				2: []string{"mention"},
			},
			useNewSubscriptions: true,
			err:                 true,
		},
		{
			name: "Returns subscribers excluding the actor",
			notifyMessage: &schema_pb.Notify{
				Actor:          &schema_pb.Notify_Actor{Id: 1},
				NotificationId: "test-notification-id",
				Context: &schema_pb.Notify_Context{
					Trigger: "create",
				},
				ExplicitRecipients: []*schema_pb.Notify_RecipientGroup{
					{Reason: "mention", UserIds: []int32{2}},
				},
				Subject: &schema_pb.Notify_Subject{Type: "Issue", Value: "1"},
				RelatedTopics: []*schema_pb.Notify_Topic{
					{Type: "repository", Value: "123"},
				},
				Attributes: []*schema_pb.Notify_Attribute{
					{Name: "added_label", Value: "1"},
				},
			},
			subscriptionRecipientIDsToReasons: notify.RecipientIDToReasons{1: {"subscribed"}, 5: {"subscribed"}},
			useNewSubscriptions:               true,
			expectedMatchFields: notify.MessageMatchFields{
				Topics: []notify.Topic{
					{Type: "repository", Value: "123"},
				},
				SubjectType:  "Issue",
				SubjectValue: "1",
				Trigger:      "create",
				Attributes: []notify.Attribute{
					{Name: "added_label", Value: "1"},
				},
			},
			expectedRecipientIDsToReasons: notify.RecipientIDToReasons{
				2: []string{"mention"},
				5: []string{"subscribed"},
			},
		},
		{
			name: "Avoids calling feature flag with only recipient is actor",
			notifyMessage: &schema_pb.Notify{
				Actor:          &schema_pb.Notify_Actor{Id: 1},
				NotificationId: "test-notification-id",
				Context: &schema_pb.Notify_Context{
					Trigger: "create",
				},
				Subject: &schema_pb.Notify_Subject{Type: "GistComment", Value: "1"},
				RelatedTopics: []*schema_pb.Notify_Topic{
					{Type: "repository", Value: "123"},
				},
			},
			subscriptionRecipientIDsToReasons: notify.RecipientIDToReasons{},
			useNewSubscriptions:               true,
			expectedMatchFields: notify.MessageMatchFields{
				Topics: []notify.Topic{
					{Type: "repository", Value: "123"},
				},
				SubjectType:  "GistComment",
				SubjectValue: "1",
				Trigger:      "create",
			},
			expectedRecipientIDsToReasons: notify.RecipientIDToReasons{},
		},
	}

	for _, test := range tests {
		ctx := context.Background()

		t.Run(test.name, func(t *testing.T) {
			subscriptionsService := new(subscriptions.ServiceMock)
			subscriptionsService.On("GetRecipientsWithReasons", mock.Anything, mock.Anything).Return(test.subscriptionRecipientIDsToReasons, nil)
			featuresClient := new(featureflags.ClientMock)
			stage := NewCalculateRecipientsStage(subscriptionsService, clock.NewMock(), logs.NullTelem, stats.NullStatter, featuresClient)

			var explicitRecipients notify.ExplicitRecipients = test.notifyMessage.GetExplicitRecipients()
			recipientIDsToReasons := explicitRecipients.ToRecipientIDToReasons()

			msg := notify.PBToNotification(test.notifyMessage)

			err := stage.AddSubscribers(ctx, recipientIDsToReasons, msg)
			r.NoError(err)
			r.Len(recipientIDsToReasons, len(test.expectedRecipientIDsToReasons))
			r.Equal(test.expectedRecipientIDsToReasons, recipientIDsToReasons)

			assertSubscriptionsServiceCalls(t, subscriptionsService, test.expectedMatchFields, test.useNewSubscriptions && !test.err)
		})
	}
}

func assertSubscriptionsServiceCalls(t *testing.T, subscriptionsService *subscriptions.ServiceMock, expectedMatchFields notify.MessageMatchFields, called bool) {
	if called {
		subscriptionsService.AssertCalled(t, "GetRecipientsWithReasons", mock.Anything, expectedMatchFields)
	} else {
		subscriptionsService.AssertNotCalled(t, "GetRecipientsWithReasons")
	}
}
