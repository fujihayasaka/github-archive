package notify

import (
	pbAny "google.golang.org/protobuf/types/known/anypb"
	"google.golang.org/protobuf/types/known/structpb"
	wrappers "google.golang.org/protobuf/types/known/wrapperspb"

	schema_pb "github.com/github/notifyd/hydro/schemas/notifyd/v0"
	entities_pb "github.com/github/notifyd/hydro/schemas/notifyd/v0/entities"
	notifyd_pb "github.com/github/notifyd/proto/notifyd/v1"
)

// PBToNotification converts a protobuf message to an internal message
func PBToNotification(msg *schema_pb.Notify) *Notification {
	var pbRecipients ExplicitRecipients = msg.GetExplicitRecipients()

	notification := Notification{
		original:   msg,
		ID:         msg.GetNotificationId(),
		ActorID:    int64(msg.GetActor().GetId()),
		Recipients: pbRecipients.ToRecipientIDToReasons(),
	}

	// deal with notification.Context
	if msg.GetContext() != nil {
		notification.Context = NotificationContext{
			Trigger:      msg.GetContext().GetTrigger(),
			RepositoryID: msg.GetContext().GetRepositoryId().GetValue(),
			OwnerID:      msg.GetContext().GetOwnerId().GetValue(),
			OwnerType:    OwnerType(msg.GetContext().GetOwnerType()),
		}
	}

	// deal with notification.FeatureSwitches
	if msg.GetFeatureSwiches() != nil {
		notification.FeatureSwitches = msg.GetFeatureSwiches()
	}

	// deal with notification.Config
	if msg.GetConfig() != nil {
		notification.Config = configFromPB(msg.GetConfig())
	}

	// handle message match fields
	notification.MessageMatchFields = extractMatchFieldsFromMessage(msg)

	return &notification
}

func extractMatchFieldsFromMessage(msg *schema_pb.Notify) MessageMatchFields {
	var topics []Topic
	var subjectType string
	var subjectValue string
	var trigger string
	var attributes []Attribute

	subject := msg.GetSubject()
	if subject != nil {
		subjectType = subject.GetType()
		subjectValue = subject.GetValue()
	}

	context := msg.GetContext()
	if context != nil {
		trigger = context.GetTrigger()
	}

	relatedTopics := msg.GetRelatedTopics()
	for _, topic := range relatedTopics {
		topics = append(topics, Topic{Type: topic.Type, Value: topic.Value})
	}

	for _, attribute := range msg.GetAttributes() {
		attributes = append(attributes, Attribute{Name: attribute.Name, Value: attribute.Value})
	}

	fields := MessageMatchFields{
		Topics:       topics,
		SubjectType:  subjectType,
		SubjectValue: subjectValue,
		Trigger:      trigger,
		Attributes:   attributes,
	}

	return fields
}

func configFromPB(pbConfig *schema_pb.Notify_Config) *NotifyConfig {
	var reasonGroups []ReasonGroup
	for _, group := range pbConfig.GetReasonGroups() {
		reasonGroups = append(reasonGroups, ReasonGroup{
			Name:    group.Name,
			Reasons: group.Reasons,
		})
	}

	return &NotifyConfig{
		ReasonGroups: reasonGroups,
	}
}

// MatchData returns the match data for the notification.
func (n Notification) MatchData() *pbAny.Any {
	data := map[string]interface{}{}

	subject := n.SubjectType
	if subject != "" {
		data["subject_type"] = subject
	}

	trigger := n.Trigger
	if trigger != "" {
		data["trigger"] = trigger
	}

	var topics []interface{}
	for _, topic := range n.Topics {
		topics = append(topics, map[string]interface{}{"type": topic.Type, "value": topic.Value})
	}

	if len(topics) > 0 {
		data["topics"] = topics
	}

	var attributes []interface{}
	for _, attr := range n.Attributes {
		attributes = append(attributes, map[string]interface{}{"name": attr.Name, "value": attr.Value})
	}

	if len(attributes) > 0 {
		data["attributes"] = attributes
	}

	value, err := structpb.NewStruct(data)
	if err != nil {
		return nil
	}

	result, _ := pbAny.New(value)
	return result
}

// TrackingPB returns the protobuf tracking data for the notification.
func (n Notification) TrackingPB() *entities_pb.Tracking {
	return n.original.Tracking
}

// SamlEnforcement returns the SAML enforcement data for the notification.
func (n Notification) SamlEnforcement() *entities_pb.SamlEnforcement {
	return n.original.GetAuthorization().GetSamlEnforcement()
}

// AuthzdAttributes returns the authzd attributes for the notification.
func (n Notification) AuthzdAttributes() []*pbAny.Any {
	return n.original.GetAuthorization().GetAuthzdAttributes()
}

// HasEmailLayout returns true if the notification has an email layout.
func (n Notification) HasEmailLayout() bool {
	return n.original.Rendering != nil && n.original.Rendering.Email != nil
}

// HasMobileLayout returns true if the notification has a mobile layout.
func (n Notification) HasMobileLayout() bool {
	return n.original.Rendering != nil && n.original.Rendering.Mobile != nil
}

// EmailLayout returns the email layout for the notification.
func (n Notification) EmailLayout() *pbAny.Any {
	return n.original.Rendering.GetEmail()
}

// MobileLayout returns the mobile layout for the notification.
func (n Notification) MobileLayout() *pbAny.Any {
	return n.original.Rendering.GetMobile()
}

// Original returns the original protobuf message.
func (n Notification) Original() *schema_pb.Notify {
	return n.original
}

// ShouldRequestPolicy returns true if the notification should request a policy.
func (n Notification) ShouldRequestPolicy() bool {
	return n.Context.HasRepository() &&
		n.Context.OwnerID != 0 &&
		n.Context.OwnerType != OwnerTypeUnknown
}

// PolicyRequestPB returns the protobuf policy request for the notification.
func (n Notification) PolicyRequestPB() *notifyd_pb.ShouldNotifyRequestContext {
	return &notifyd_pb.ShouldNotifyRequestContext{
		RepositoryId: wrappers.Int64(n.Context.RepositoryID),
		//nolint:gosec // Known issue https://github.com/github/notifyd/issues/3113
		ActorId: int32(n.ActorID),
		OwnerId: wrappers.Int64(n.Context.OwnerID),
	}
}
