package events

import (
	"context"

	"github.com/golang/protobuf/proto" // nolint:staticcheck
)

// Publisher is the expected interface that we use to publish Events.
type Publisher interface {
	Publish(ctx context.Context, messages []proto.Message, partitionKey string) error
}
