package hydro

import (
	"github.com/golang/protobuf/proto" // nolint: staticcheck
)

// Client defines the interface to the Hydro Client
type Client interface {
	Publish(messages []proto.Message, partitionKey string) error
}
