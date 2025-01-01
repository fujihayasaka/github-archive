package chatopsserver

import (
	"context"
	"encoding/json"
	"fmt"
	"strconv"
	"strings"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/go-auth/hmac"
	"github.com/github/go-chatops/v2"

	schema_pb_v0 "github.com/github/notifyd/hydro/schemas/notifyd/v0"
	dto "github.com/github/notifyd/internal/pkg/notify"
	"github.com/github/notifyd/internal/pkg/notify/stages"
)

// PingChatop implements the ping command.
func PingChatop() *chatops.GenericChatop {
	return chatops.NewGenericChatop(
		"ping",
		"ping - get a pong back from Notifyd service",
		"ping",
		func(ctx context.Context, req *chatops.CommandRequest) (*chatops.CommandResponse, error) {
			return &chatops.CommandResponse{
				Result: "pong",
			}, nil
		},
	)
}

// RouteTest implements the view-route command.
func RouteTest(s stages.IRouteRecipientsToChannelsStage) *chatops.GenericChatop {
	return chatops.NewGenericChatop(
		"view-route",
		"view-route message={\"notification_id\":\"test-notification-id\", \"related_topics\":[{\"type\":\"repository\",\"value\":\"123\"}],\"subject\":{\"type\":\"Issue\",\"value\":\"1\"}} recipient=user.id reason=\"reason\" - to test routing",
		`view-route\s*message=(?<message>.*\})\s*recipient=(?<recipient>\d+)\s*reason=(?<reason>\w+)`,
		func(ctx context.Context, req *chatops.CommandRequest) (*chatops.CommandResponse, error) {
			message := req.Params["message"]
			var notify schema_pb_v0.Notify
			err := json.Unmarshal([]byte(message), &notify)
			if err != nil {
				//nolint:nilerr // we're handling the error here, no need to propagate it
				return &chatops.CommandResponse{
					Result: "message parsing error",
				}, nil
			}

			reason := req.Params["reason"]

			recipient := req.Params["recipient"]
			recipientInt, err := strconv.ParseInt(recipient, 10, 32)
			if err != nil {
				//nolint:nilerr // we're handling the error here, no need to propagate it
				return &chatops.CommandResponse{
					Result: "recipient parsing error",
				}, nil
			}

			recipientToReasons := dto.RecipientIDToReasons{
				recipientInt: []string{reason},
			}

			msg := dto.PBToNotification(&notify)
			data := s.RouteRecipientsToChannels(ctx, recipientToReasons, msg)
			enabledChannels := ""
			for _, channel := range data[recipientInt].Channels {
				if channel.Enabled {
					enabledChannels += channel.Channel + " "
				}
			}

			return &chatops.CommandResponse{
				Result: fmt.Sprintf("The message would be routed to the following channels: %s", enabledChannels),
			}, nil
		},
	)
}

// HMACChatop implements the hmac command.
func HMACChatop(apiKeys string, telem *telemetry.Provider) *chatops.GenericChatop {
	return chatops.NewGenericChatop(
		"hmac",
		"hmac - get an HMAC token for the Notifyd service",
		"hmac",
		func(ctx context.Context, req *chatops.CommandRequest) (*chatops.CommandResponse, error) {
			telem.Logger.WithFields(
				kvp.String("gh.notifyd.chatops.room.id", req.RoomID),
				kvp.String("gh.notifyd.chatops.user", req.User),
			).
				WithContext(ctx).
				Info("creation of HMAC token")
			var key string
			keys := strings.Split(apiKeys, "")
			if len(keys) > 0 {
				key = keys[0]
			}
			hmac := hmac.NewRequestHMAC(key)
			return &chatops.CommandResponse{
				Result: hmac.String(),
			}, nil
		},
	)
}
