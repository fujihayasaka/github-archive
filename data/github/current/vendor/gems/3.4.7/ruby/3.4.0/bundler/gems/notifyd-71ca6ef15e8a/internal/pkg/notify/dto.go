// Package notify implements the pipeline for processing notifications.
package notify

import (
	schema_pb "github.com/github/notifyd/hydro/schemas/notifyd/v0"
	"github.com/github/notifyd/internal/pkg/errors"

	"google.golang.org/protobuf/types/known/anypb"
	"google.golang.org/protobuf/types/known/structpb"
)

// OwnerType values.
const (
	OwnerTypeUnknown OwnerType = 0
	OwnerTypeUser    OwnerType = 1
	OwnerTypeOrg     OwnerType = 2
)

// Errors for missing fields.
var (
	ErrNoRelatedTopics = errors.New("Missing related topics")
	ErrNoSubject       = errors.New("Missing subject")
	ErrNoSubjectType   = errors.New("Missing subject type")
	ErrNoTrigger       = errors.New("Missing trigger")
)

// Notification is the internal representation of a notification
type Notification struct {
	original   *schema_pb.Notify
	ID         string
	ActorID    int64
	Recipients RecipientIDToReasons
	MessageMatchFields

	Context NotificationContext

	FeatureSwitches map[string]bool
	Config          *NotifyConfig
}

// MessageMatchFields represents the fields that are used to match a message.
type MessageMatchFields struct {
	Topics       []Topic
	SubjectType  string
	SubjectValue string
	Trigger      string
	Attributes   []Attribute
}

// NotificationContext represents the context of a notification.
type NotificationContext struct {
	Trigger      string // TODO: this value does not seemed to be used anywhere, it's part of match fields
	RepositoryID int64
	OwnerID      int64
	OwnerType    OwnerType
}

// OwnerType represents the type of an owner.
type OwnerType int32

// Matchable returns an error if the message is not matchable.
func (m MessageMatchFields) Matchable() error {
	if len(m.Topics) == 0 {
		return ErrNoRelatedTopics
	}

	if m.SubjectValue == "" {
		return ErrNoSubject
	}

	if m.SubjectType == "" {
		return ErrNoSubjectType
	}

	if m.Trigger == "" {
		return ErrNoTrigger
	}

	return nil
}

// HasRepository returns true if the notification has a repository.
func (nc NotificationContext) HasRepository() bool {
	return nc.RepositoryID != 0
}

// ReasonGroups returns the reason groups.
func (n Notification) ReasonGroups() []ReasonGroup {
	var reasonGroups []ReasonGroup
	if n.Config != nil {
		reasonGroups = n.Config.ReasonGroups
	}
	return reasonGroups
}

// ExtractArbitraryMatchDataFromMessage extracts arbitrary match data from a message.
func ExtractArbitraryMatchDataFromMessage(msg *schema_pb.Notify) (*anypb.Any, error) {
	data := map[string]interface{}{}

	subject := msg.GetSubject()
	if subject != nil {
		data["subject_type"] = subject.GetType()
	}

	context := msg.GetContext()
	if context != nil {
		data["trigger"] = context.GetTrigger()
	}

	msgTopics := msg.GetRelatedTopics()

	topics := []interface{}{}
	for _, topic := range msgTopics {
		topics = append(topics, map[string]interface{}{"type": topic.Type, "value": topic.Value})
	}

	if len(topics) > 0 {
		data["topics"] = topics
	}

	msgAttributes := msg.GetAttributes()
	attributes := []interface{}{}
	for _, attr := range msgAttributes {
		attributes = append(attributes, map[string]interface{}{"name": attr.Name, "value": attr.Value})
	}

	if len(attributes) > 0 {
		data["attributes"] = attributes
	}

	value, err := structpb.NewStruct(data)
	if err != nil {
		return nil, err
	}

	return anypb.New(value)
}

// Topic represents a topic.
type Topic struct {
	Type  string
	Value string
}

// Attribute represents an attribute.
type Attribute struct {
	Name  string
	Value string
}

// NotifyConfig represents the configuration of a notification.
type NotifyConfig struct { //nolint:revive // This name refers to the Notify topic
	ReasonGroups []ReasonGroup
}

// ReasonGroup represents a group of reasons.
type ReasonGroup struct {
	Name    string
	Reasons []string
}
