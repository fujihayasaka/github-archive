package chatops

// CommandRequest represents a message from a Chatops RPC bot, delivered as an
// HTTP POST with serialized JSON.
type CommandRequest struct {
	Method     string            `json:"method"`
	Params     map[string]string `json:"params"`
	User       string            `json:"user"`
	RoomID     string            `json:"room_id"`
	RawCommand string            `json:"raw_command"`
	MessageID  string            `json:"message_id"`
}

// CommandButton represents a button in a response to a Chatops RPC bot request.
type CommandButton struct {
	Label    string `json:"label,omitempty"`
	ImageURL string `json:"image_url,omitempty"`
	Command  string `json:"command,omitempty"`
}

// ThreadStyle indicates the desired style of reply when using the Slack adapter. This is defined as
// a feature in the Hubot RPC spec (and not tied to Slack or its API implementation, notably):
// https://github.com/github/hubot-classic/blob/master/docs/rpc_chatops_protocol.md#executing-commands
type ThreadStyle int

const (
	// ThreadStyleChannel toggles replying in a channel.
	ThreadStyleChannel ThreadStyle = 0
	// ThreadStyleThreaded toggles replying in a thread.
	ThreadStyleThreaded ThreadStyle = 1
	// ThreadStyleThreadedAndChannel toggles replying in both the thread and also sent to channel.
	ThreadStyleThreadedAndChannel ThreadStyle = 2
)

// CommandResponse represents a message response to a Chatops RPC bot, after
// handling the CommandRequest message.
type CommandResponse struct {
	Result         string          `json:"result"`
	Title          string          `json:"title,omitempty"`
	TitleLink      string          `json:"title_link,omitempty"`
	Color          string          `json:"color,omitempty"`
	ImageURL       string          `json:"image_url,omitempty"`
	Buttons        []CommandButton `json:"buttons,omitempty"`
	Attachment     bool            `json:"attachment,omitempty"`
	AttachmentName string          `json:"attachment_name,omitempty"`
	ThreadStyle    ThreadStyle     `json:"thread_style,omitempty"`
}
