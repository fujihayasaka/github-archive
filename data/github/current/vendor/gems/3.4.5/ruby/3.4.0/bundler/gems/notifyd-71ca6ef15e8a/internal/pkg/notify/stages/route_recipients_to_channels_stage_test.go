package stages

import (
	"context"
	"testing"

	"github.com/benbjohnson/clock"
	"github.com/github/go-stats"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"

	schema_pb "github.com/github/notifyd/hydro/schemas/notifyd/v0"
	"github.com/github/notifyd/internal/pkg/notify"
	"github.com/github/notifyd/internal/pkg/o11y/logs"
	"github.com/github/notifyd/internal/pkg/routing"
)

func TestRouteRecipientsToChannelsStage_Execute(t *testing.T) {
	r := require.New(t)

	notifyMessage := &schema_pb.Notify{
		Actor:          &schema_pb.Notify_Actor{Id: 1},
		NotificationId: "test-notification-id",
		Context: &schema_pb.Notify_Context{
			Trigger: "create",
		},
		ExplicitRecipients: []*schema_pb.Notify_RecipientGroup{
			{Reason: "mention", UserIds: []int32{2}},
		},
		Subject: &schema_pb.Notify_Subject{Type: "Issue", Value: "1"},
	}

	recipients := notify.RecipientIDToReasons{
		2: []string{"subscribed"},
		3: []string{"subscribed"},
	}

	mockDeliveryMetadata := notify.RecipientToDeliveryMetadata{
		2: {Channels: routing.ToChannelsMap(map[string]bool{"PUSH": false, "EMAIL": true}), Reasons: []string{"subscribed"}},
		3: {Channels: routing.ToChannelsMap(map[string]bool{"PUSH": false, "EMAIL": true}), Reasons: []string{"subscribed"}},
	}

	ctx := context.Background()
	msg := notify.PBToNotification(notifyMessage)

	query := routing.NewMatchQuery(msg.ID, msg.ActorID, msg.MessageMatchFields, msg.ReasonGroups())

	routingSettingsServiceMock := new(routing.ServiceMock)
	routingSettingsServiceMock.On("GetDeliveryMetadata", mock.Anything, recipients, query).Return(mockDeliveryMetadata)

	stage := NewRouteRecipientsToChannelsStage(routingSettingsServiceMock, clock.NewMock(), logs.NullTelem, stats.NullStatter)
	actualRecipientsToDeliveryMetadataEntries := stage.RouteRecipientsToChannels(ctx, recipients, msg)

	r.Equal(actualRecipientsToDeliveryMetadataEntries, mockDeliveryMetadata)

	routingSettingsServiceMock.AssertCalled(t, "GetDeliveryMetadata", mock.Anything, recipients, query)
}
