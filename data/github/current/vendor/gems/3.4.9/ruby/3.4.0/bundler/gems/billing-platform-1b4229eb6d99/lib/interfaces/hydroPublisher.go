package interfaces

import (
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	"google.golang.org/protobuf/proto"
)

//go:generate pegomock generate -o ../../testing/fakes/mock_hydropublisher.go --self_package=fakes --package=fakes HydroPublisher
type HydroPublisher interface {
	Publish(m proto.Message, opts ...hydro.PublishOption) error
}
