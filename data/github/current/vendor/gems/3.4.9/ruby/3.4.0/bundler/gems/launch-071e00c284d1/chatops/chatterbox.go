package chatops

import (
	"github.com/github/go-chatops/v2/security"
	"github.com/github/go-chatterbox"
)

func NewChatClient(baseURL, token string) (security.Prompter, error) {
	client, err := chatterbox.New(token, baseURL)
	if err != nil {
		return nil, err
	}

	return &chatClient{
		client: client,
	}, nil
}

type chatClient struct {
	client *chatterbox.Client
}

// Speak is an adapter method so that chatterbox.Client implements security.Prompter
func (c *chatClient) Speak(channel, message string) error {
	return c.client.Say(channel, message)
}
