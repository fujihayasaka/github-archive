package chat

import (
	"context"

	"github.com/github/go-kvp"
	"github.com/github/go-telemetry/logging"
)

const BlackbirdOpsChannel = "#blackbird-ops"

// Infallible function to output a message to a chat room.
func Say(ctx context.Context, client Client, channel, msg string) {
	if client == nil {
		logging.Error(ctx, "message not sent: no chat client configured", kvp.String("say_msg", msg), kvp.String("channel", channel))
		return
	}
	if err := client.Say(channel, msg); err != nil {
		logging.Error(ctx, "error posting message to room", kvp.Err(err), kvp.String("channel", channel))
	}
}
