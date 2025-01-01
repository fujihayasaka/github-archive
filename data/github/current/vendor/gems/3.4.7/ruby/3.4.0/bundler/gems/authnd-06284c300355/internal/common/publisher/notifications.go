package publisher

import (
	"context"
	"fmt"
	"time"

	"github.com/github/authnd/internal/common/config"
	notifydProto "github.com/github/authnd/internal/common/publisher/hydro/schemas/notifyd/v0"
	entityProto "github.com/github/authnd/internal/common/publisher/hydro/schemas/notifyd/v0/entities"
	authzdProto "github.com/github/authzd/pkg/proto"
	layoutProto "github.com/github/notifyd/proto/layouts/mobile"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/anypb"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/github/hydro-client-go/v7/pkg/hydro"
	"github.com/pkg/errors"
)

var TypeUrl = "type.googleapis.com/notifyd.layouts.mobile.Basic"

// NotificationPublisher triggers NotifyD github mobile notifications for mobile auth requests.
type NotificationPublisher interface {
	PublishNotification(ctx context.Context, userId int64, layoutData *layoutProto.Basic, now time.Time) error
	Publisher
}

type notificationPublisher struct {
	topic string
	Publisher
}

type NullPublisher struct {
	Publisher
}

func NewNotificationPublisher(ctx context.Context, commonConfig *config.CommonConfig, withSink func(hydro.KafkaConfig) (hydro.Sink, error)) (NotificationPublisher, error) {
	// Enterprise shouldn't publish any mobile notifications, but due to server calling publisher.Close() on stop() we need some implementation of Close() to avoid erroring
	if commonConfig.IsEnterpriseServer {
		return &NullPublisher{}, nil
	}

	publisher, err := NewPublisher(ctx, commonConfig, commonConfig.KafkaPotomacBrokers, hydro.TopicFormatV2, withSink)
	if err != nil {
		return nil, errors.WithStack(err)
	}
	return &notificationPublisher{
		Publisher: publisher,
		topic:     "notifyd.v1.Notify",
	}, nil
}

func (p *notificationPublisher) PublishNotification(ctx context.Context, userId int64, layoutData *layoutProto.Basic, now time.Time) error {
	layoutBytes, err := proto.Marshal(layoutData)
	if err != nil {
		return errors.WithStack(err)
	}

	msg := &notifydProto.Notify{
		ExplicitRecipients: []*notifydProto.Notify_RecipientGroup{
			{Reason: "mobile_auth_request", UserIds: []int32{int32(userId)}},
		},
		Rendering: &notifydProto.Notify_Rendering{
			Mobile: &anypb.Any{
				TypeUrl: TypeUrl,
				Value:   layoutBytes,
			},
		},
		NotificationId: fmt.Sprintf("mobile-auth-request/user-%d-%s", userId, now.Format(time.RFC3339)),
		Authorization: &notifydProto.Notify_Authorization{
			AuthzdAttributes: []*anypb.Any{
				wrapAuthzAttribute("subject.user_id", authzdProto.NewInt64Value(userId)),
				wrapAuthzAttribute("subject.type", authzdProto.NewStringValue("Authnd::MobileAuthRequest")),
			},
			SamlEnforcement: &entityProto.SamlEnforcement{
				SkipEnforcement: true,
			},
		},
		Tracking: &entityProto.Tracking{
			TriggeredAt: timestamppb.New(time.Now()),
		},
	}

	return p.PublishMessage(ctx, p.topic, msg)
}

func (np *NullPublisher) PublishNotification(ctx context.Context, userId int64, layoutData *layoutProto.Basic, now time.Time) error {
	return errors.New("Cannot publish notification with null publisher")
}

func wrapAuthzAttribute(id string, value *authzdProto.Value) *anypb.Any {
	attribute := authzdProto.Attribute{
		Id:    id,
		Value: value,
	}
	wrappedAttribute, err := anypb.New(&attribute)
	if err != nil {
		panic(err)
	}

	return wrappedAttribute
}
