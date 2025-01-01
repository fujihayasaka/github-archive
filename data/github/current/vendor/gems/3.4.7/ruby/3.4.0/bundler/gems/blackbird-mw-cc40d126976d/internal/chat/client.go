package chat

import (
	"github.com/github/go-kvp"
	"github.com/github/go-telemetry/logging"
)

// Client is an interface for wrapping a chatterbox.Client because it doesn't
// have a no-op implementation.
//
// A *chatterbox.Client will satisfy this interface.
type Client interface {
	Say(topic string, message string) error
}

type NoopClient struct{}

func (n *NoopClient) Say(topic string, message string) error {
	logging.GetLogger().Info("noop chatterbox client: say", kvp.String("topic", topic), kvp.String("message", message))
	return nil
}
