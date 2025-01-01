package events

import (
	"github.com/golang/protobuf/proto" // nolint: staticcheck
)

// NewHydroEvent creates a new Event with existing messages.
func NewHydroEvent(eventType string, messages ...proto.Message) Event {
	return &hydroEvent{messages: messages, eventType: eventType}
}

func NewHydroEventFromSlice(eventType string, messages []proto.Message) Event {
	return &hydroEvent{messages: messages, eventType: eventType}
}

type hydroEvent struct {
	messages  []proto.Message
	eventType string
}

func (e *hydroEvent) GetHydroMessages() []proto.Message {
	return e.messages
}

func (e *hydroEvent) GetEventType() string {
	if e.eventType == "" {
		return "unknown"
	}

	return e.eventType
}
