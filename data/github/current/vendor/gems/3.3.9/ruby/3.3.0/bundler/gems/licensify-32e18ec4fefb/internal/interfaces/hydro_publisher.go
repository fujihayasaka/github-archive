// Package interfaces provides the HydroPublisher interface.
package interfaces

import (
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	//nolint:staticcheck // ignore the following import as it is required for the interface since the HydroPublisher uses the deprecated package.
	"google.golang.org/protobuf/proto"
)

// HydroPublisher is an interface for publishing messages to Hydro.
type HydroPublisher interface {
	Publish(m proto.Message, opts ...hydro.PublishOption) error
}
