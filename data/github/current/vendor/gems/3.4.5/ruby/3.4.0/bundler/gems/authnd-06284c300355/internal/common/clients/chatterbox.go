package clients

import (
	"context"
	"fmt"
	"strings"

	"github.com/github/authnd/internal/common/diagnostics"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-chatops/v2/security"
	"github.com/github/go-chatterbox"
	"github.com/pkg/errors"
)

const (
	defaultAuthndChatopsRoomID = "#authnd-ops"
)

type ChatterboxClient interface {
	PostMessageToSlack(ctx context.Context, message string)
	LogAndPostMessageToSlack(ctx context.Context, message string, kind string)

	security.Prompter
}

type chatterboxClient struct {
	client    *chatterbox.Client
	logPrefix string
}

func NewChatterboxClient(logPrefix string, token string, url string) (ChatterboxClient, error) {
	client, err := chatterbox.New(token, url)
	if err != nil {
		return nil, errors.WithStack(err)
	}
	return &chatterboxClient{
		client:    client,
		logPrefix: logPrefix,
	}, nil
}

func (c *chatterboxClient) Speak(channel, message string) error {
	return c.client.Say(channel, message)
}

func (c *chatterboxClient) PostMessageToSlack(ctx context.Context, message string) {
	chatRoom := GetChatRoom(ctx)
	if c.logPrefix != "" {
		message = fmt.Sprintf("[%s] %s", c.logPrefix, message)
	}
	err := c.Speak(chatRoom, message)
	if err != nil {
		// Log failures, but don't return an error since we don't want to stop the process just because we couldn't talk to Chatterbox.
		diagnostics.Logger(ctx).WithError(err).Error("failed to post Chatterbox message to Slack",
			kvp.String("room", chatRoom),
			kvp.String("message", message))
	}
}

func (c *chatterboxClient) LogAndPostMessageToSlack(ctx context.Context, message string, kind string) {
	switch strings.ToLower(kind) {
	case "info":
		diagnostics.Logger(ctx).Info(message)
	case "error":
		diagnostics.Logger(ctx).Error(message)
	}

	c.PostMessageToSlack(ctx, message)
}

type developmentChatterboxClient struct{}

func NewDevelopmentChatterboxClient() ChatterboxClient {
	return &developmentChatterboxClient{}
}

func (c *developmentChatterboxClient) Speak(channel, message string) error {
	// 2FA prompts for chatops aren't available in dev
	return nil
}

func (c *developmentChatterboxClient) PostMessageToSlack(ctx context.Context, message string) {
	diagnostics.Logger(ctx).Info("[Chatterbox Client]", kvp.String("gh.authnd.chatterbox.message", message), kvp.String("gh.authnd.chatterbox.room", GetChatRoom(ctx)))
}

func (c *developmentChatterboxClient) LogAndPostMessageToSlack(ctx context.Context, message string, kind string) {
	diagnostics.Logger(ctx).Info("[Chatterbox Client]", kvp.String("gh.authnd.chatterbox.message", message), kvp.String("gh.authnd.chatterbox.room", GetChatRoom(ctx)))
}

type chatRoomKey struct{}

func WithChatRoom(ctx context.Context, roomID string) context.Context {
	return context.WithValue(ctx, chatRoomKey{}, roomID)
}

func GetChatRoom(ctx context.Context) string {
	v := ctx.Value(chatRoomKey{})
	if s, ok := v.(string); ok {
		return s
	}
	return defaultAuthndChatopsRoomID
}
