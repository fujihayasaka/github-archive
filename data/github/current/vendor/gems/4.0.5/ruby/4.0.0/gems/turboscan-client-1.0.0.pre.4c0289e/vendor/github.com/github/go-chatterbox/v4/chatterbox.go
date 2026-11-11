// Package chatterbox sends messages to chatterbox, GitHub's API for sending
// messages into chat.
//
// To send a message, without creating a Client, use Say:
//
//	_, err := chatterbox.Say(ctx, token, url, chatterbox.SayPayload{Topic: "dumping-ground", Text: "Hello, world!"})
//	...
//
// To create a client:
//
//	client := chatterbox.New(token, url)
//	_, err := client.Say(ctx, chatterbox.SayPayload{Topic: "dumping-ground", Text: "Hello, world!"})
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

// Client is the interface for sending messages to chatterbox.
type Client interface {
	Say(context.Context, SayPayload) (string, error)
	WithHTTPClient(*http.Client) Client
}

// SayPayload contains options for the Say method.
type SayPayload struct {
	// Text to send. Either Text or Message must be set.
	Text string
	// Message to send. Either Text or Message must be set.
	Message *Message
	// Topic to send the message to.
	Topic string
	// ThreadID is the ID of the thread to reply to. If empty, a new message is posted.
	ThreadID string
	// If true, the message is posted to the channel as well as the thread.
	Broadcast bool
	// If true, the response will include the thread ID of the message sent.
	// This option is only supported for topics with a single subscription (usually explicit channel name).
	ReturnThreadID bool
}

// chatClient is an authenticated client used for sending messages to chatterbox.
type chatClient struct {
	token      string
	httpClient *http.Client
	parsedURL  *url.URL
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

// NewMessage creates a new Message with the given text.
func NewMessage(message string) *Message {
	return &Message{
		text: message,
	}
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

// NewClient returns a new chatterbox.Client which can be used for sending things
// to chatterbox via client.Say(...)
func NewClient(token, chatterboxURL string) (Client, error) {
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

	return &chatClient{
		token:      token,
		httpClient: &http.Client{},
		parsedURL:  parsedURL}, nil
}

// WithHTTPClient sets the http.Client to use for sending messages to chatterbox.
func (c *chatClient) WithHTTPClient(client *http.Client) Client {
	c.httpClient = client
	return c
}

// Say posts a message to the given topic. Returns thread id if requested or an error if something went wrong.
func (c *chatClient) Say(ctx context.Context, opts SayPayload) (string, error) {
	if opts.Text != "" && opts.Message != nil {
		return "", errors.New("either Text or Message must be set, not both")
	}

	if opts.Message == nil {
		if opts.Text == "" {
			return "", errors.New("either Text or Message must be set")
		}
		opts.Message = NewMessage(opts.Text)
	}

	if opts.Topic == "" {
		return "", errors.New("topic must not be empty")
	}

	return c.sayMessage(ctx, opts)
}

// Say posts a message to the given topic, but without requiring a new chatterbox.Client
// to be created. Returns thread id if requested and an error if something went wrong.
func Say(ctx context.Context, token, chatterboxURL string, opts SayPayload) (string, error) {
	c, err := NewClient(token, chatterboxURL)
	if err != nil {
		return "", err
	}

	return c.Say(ctx, opts)
}

func (c *chatClient) sayMessage(ctx context.Context, opts SayPayload) (string, error) {
	requestURL := fmt.Sprintf("%s/topics/%s", c.parsedURL, url.PathEscape(opts.Topic))
	if opts.ThreadID != "" {
		// rails appends `(.:format)` to the end of routes (see https://guides.rubyonrails.org/routing.html) but
		// `url.PathEscape` does not escape `.`, so we have to do it ourselves since threadID contains a `.`
		requestURL += "/" + strings.ReplaceAll(url.PathEscape(opts.ThreadID), ".", "%2E")
		if opts.Broadcast {
			requestURL += "/true"
		}
	}

	if opts.ReturnThreadID {
		requestURL += "?return_thread_id=true"
	}

	r, err := opts.Message.encode()
	if err != nil {
		return "", fmt.Errorf("failed to encode message to json: %w", err)
	}

	body, err := c.post(ctx, requestURL, r)
	if err != nil {
		return "", err
	}

	if !opts.ReturnThreadID {
		return "", nil
	}

	var resp struct {
		ThreadID string `json:"thread_id"`
	}
	if err := json.Unmarshal([]byte(body), &resp); err != nil {
		return "", fmt.Errorf("failed to unmarshal chatterbox response: %w", err)
	}

	return resp.ThreadID, nil
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

// post posts the message to chatterbox. If the HTTP status code is 200 or 201, the body of the
// response is returned.
func (c *chatClient) post(ctx context.Context, requestURL string, data io.Reader) (string, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, requestURL, data)
	if err != nil {
		return "", err
	}
	req.SetBasicAuth(c.token, "X")
	req.Header.Add("Content-Type", "application/json; charset=utf-8")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return "", errors.New("failed to post http request to chatterbox endpoint")
	}
	defer resp.Body.Close()

	var buf bytes.Buffer
	if _, err := io.Copy(&buf, resp.Body); err != nil {
		return "", err
	}

	// Check for non-200(1) status code
	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusCreated {
		return "", fmt.Errorf("failed to post message to chatterbox; status code %d: %s", resp.StatusCode, buf.String())
	}

	return buf.String(), nil
}
