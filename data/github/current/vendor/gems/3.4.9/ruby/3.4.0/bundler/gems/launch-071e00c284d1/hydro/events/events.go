package events

import (
	// nolint: staticcheck
	"github.com/golang/protobuf/proto"
)

// Event is the expected interface which the Publisher can publish
type Event interface {
	// GetHydroMessages returns the Hydro messages for this Event
	GetHydroMessages() []proto.Message

	// GetEventType returns the type of the Evvent
	GetEventType() string
}
