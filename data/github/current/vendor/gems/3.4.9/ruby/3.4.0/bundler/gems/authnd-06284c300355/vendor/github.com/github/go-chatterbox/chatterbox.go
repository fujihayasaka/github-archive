// Package chatterbox sends messages to chatterbox, GitHub's API for sending
// messages into chat.
//
// To send a message, without creating a Client, use Say:
//
//	err := chatterbox.Say(token, url, "my topic", "hello, world!")
//	...
//
// To create a client:
//
//	client := chatterbox.New(token, url)
//	err := client.Say("my topic", "hello, world!")
//	...
package chatterbox

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"

	"github.com/slack-go/slack"
)

// Usual colors, taken from ruby client.
const (
	GREEN  = "#4B9611"
	RED    = "#CC1D34"
	YELLOW = "#EBD249"
)

// Client is an authenticated client used for sending messages to chatterbox.
type Client struct {
	token      string
	httpClient *http.Client
	parsedURL  *url.URL
}

// New returns a new chatterbox.Client which can be used for sending things
// to chatterbox via client.Say(...)
func New(token, chatterboxURL string) (*Client, error) {
	if token == "" {
		return nil, errors.New("token must not be empty")
	}
	if chatterboxURL == "" {
		return nil, errors.New("chatterboxURL must not be empty")
	}

	parsedURL, err := url.Parse(chatterboxURL)
	if err != nil {
		return nil, err
	}

	return &Client{
		token:      token,
		httpClient: &http.Client{},
		parsedURL:  parsedURL}, nil
}

// Say posts a message to the given topic. Returns an error, or nil if everything succeeded.
func (c *Client) Say(topic, message string) error {
	m := NewMessage(message)
	return c.sayMessage(topic, "", false, m)
}

// SayThreaded posts a message to the given topic,
// but if threadID is non-empty (e.g., "1630688879.052800"), then it replies in the specified Slack thread.
// If broadcast is true then it replies in the specified Slack thread and also posts to the Slack channel.
// Returns an error, or nil if everything succeeded.
func (c *Client) SayThreaded(topic, threadID string, broadcast bool, message string) error {
	m := NewMessage(message)
	return c.sayMessage(topic, threadID, broadcast, m)
}

// SayThreadedMessage posts a message to the given topic,
// but if threadID is non-empty (e.g., "1630688879.052800"), then it replies in the specified Slack thread.
// If broadcast is true then it replies in the specified Slack thread and also posts to the Slack channel.
// Returns an error, or nil if everything succeeded.
func (c *Client) SayThreadedMessage(topic, threadID string, broadcast bool, msg *Message) error {
	return c.sayMessage(topic, threadID, broadcast, msg)
}

// SayMessage posts a message to the given topic. Returns an error, or nil if everything succeeded.
func (c *Client) SayMessage(topic string, msg *Message) error {
	return c.sayMessage(topic, "", false, msg)
}

func (c *Client) sayMessage(topic, threadID string, broadcast bool, msg *Message) error {
	requesturl := fmt.Sprintf("%s/topics/%s", c.parsedURL, url.PathEscape(topic))
	if threadID != "" {
		// rails appends `(.:format)` to the end of routes (see https://guides.rubyonrails.org/routing.html) but
		// `url.PathEscape` does not escape `.`, so we have to do it ourselves since threadID contains a `.`
		requesturl += "/" + strings.ReplaceAll(url.PathEscape(threadID), ".", "%2E")
		if broadcast {
			requesturl += "/true"
		}
	}

	r, err := msg.encode()
	if err != nil {
		return fmt.Errorf("failed to encode message to json: %w", err)
	}
	return c.post(requesturl, r)
}

// post posts the message to chatterbox.
func (c *Client) post(requestURL string, data io.Reader) error {
	req, err := http.NewRequestWithContext(context.Background(), http.MethodPost, requestURL, data)
	if err != nil {
		return err
	}
	req.SetBasicAuth(c.token, "X")
	req.Header.Add("Content-Type", "application/json; charset=utf-8")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	return nil
}

// Say posts a message to the given topic, but without requiring a new
// chatterbox.Client to be created. Returns an error or nil if everything
// succeeded.
func Say(token, chatterboxURL, topic, message string) error {
	c, err := New(token, chatterboxURL)
	if err != nil {
		return err
	}

	return c.Say(topic, message)
}

// SayMessage posts a message to the given topic, but without requiring a new
// chatterbox.Client to be created. Returns an error or nil if everything
// succeeded.
func SayMessage(token, chatterboxURL, topic string, message *Message) error {
	c, err := New(token, chatterboxURL)
	if err != nil {
		return err
	}

	return c.SayMessage(topic, message)
}

// Message is a structure for sending more complex messages to chatterbox than
// just simple plaintext.
type Message struct {
	text           string
	textAttachment *textAttachment
	blocks         []slack.Block
}

// textAttachment is an internally used structure to represent a message's rich
// text.
type textAttachment struct {
	Text     string `json:"text"`
	Fallback string `json:"fallback"`
	Color    string `json:"color,omitempty"`
	Footer   string `json:"footer,omitempty"`
}

// encode coverts the Message structure into a JSON representation and
// returns an io.Reader representation for use by http.Request.
func (m *Message) encode() (io.Reader, error) {
	msg := map[string]interface{}{
		"text": m.text,
	}
	if m.textAttachment != nil {
		msg["attachments"] = []*textAttachment{m.textAttachment}
	}
	if len(m.blocks) >= 1 {
		msg["blocks"] = m.blocks
	}
	b := new(bytes.Buffer)
	err := json.NewEncoder(b).Encode(msg)
	if err != nil {
		return nil, err
	}
	return b, nil
}

// Color sets the slack stripe alongside the message to the given color.
func (m *Message) Color(color string) {
	m.ensureTextAttachment()
	m.textAttachment.Color = color
}

// Footer adds a small footer in slack (slack-specific feature).
func (m *Message) Footer(footer string) {
	m.ensureTextAttachment()
	m.textAttachment.Footer = footer
}

// Blocks sets blocks (slack-specific feature).
func (m *Message) Blocks(blocks []slack.Block) {
	m.blocks = blocks
}

// ensureTextAttachment checks that the message has an attachment,
// and if not, creates one and initializes the required fields.
func (m *Message) ensureTextAttachment() {
	if m.textAttachment == nil {
		m.textAttachment = &textAttachment{
			Text:     m.text,
			Fallback: m.text,
		}
	}
}

// NewMessage creates a new Message with the given text.
func NewMessage(message string) *Message {
	return &Message{
		text: message,
	}
}
