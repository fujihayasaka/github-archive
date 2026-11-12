// Package syncmux provides a topic-based multiplexer for routing Hydro messages
// to different sync handlers based on the message topic.
package syncmux

import (
	"context"

	hydro_lib "github.com/github/hydro-client-go/v7/pkg/hydro"
)

// Mux routes Hydro messages to handlers based on the message topic.
type Mux struct {
	handlers map[string]hydro_lib.MessageHandler
}

// New creates a Mux that routes messages by topic to the given handlers.
func New(handlers map[string]hydro_lib.MessageHandler) *Mux {
	return &Mux{handlers: handlers}
}

// Dispatch routes the message to the appropriate handler based on its topic.
// Messages for unregistered topics are silently acknowledged to prevent
// consumer failures when not all Sync topics have registered handlers.
func (m *Mux) Dispatch(ctx context.Context, msg hydro_lib.Message) error {
	if h, ok := m.handlers[msg.Topic]; ok {
		return h(ctx, msg)
	}
	return nil
}
