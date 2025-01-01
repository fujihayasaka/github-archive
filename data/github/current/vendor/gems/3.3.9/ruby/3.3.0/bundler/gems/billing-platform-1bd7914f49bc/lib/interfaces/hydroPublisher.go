package interfaces

import (
	"github.com/github/hydro-client-go/v5/pkg/hydro"

	// ignore the following import as it is required for the interface
	// since the HydroPublisher uses the deprecated package.
	// nolint: staticcheck
	"github.com/golang/protobuf/proto"
)

type HydroPublisher interface {
	Publish(m proto.Message, opts ...hydro.PublishOption) error
}
