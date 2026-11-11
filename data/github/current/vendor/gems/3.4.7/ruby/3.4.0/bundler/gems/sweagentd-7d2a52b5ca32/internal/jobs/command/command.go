package command

import (
	"errors"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	"github.com/google/uuid"
)

// ErrJobIsTerminal is returned when attempting to add a command to a job that is
// in a terminal state ("completed", "failed", "canceled", "timed_out").
var ErrJobIsTerminal = errors.New("cannot add command to terminal job")

// Command represents a command to be delivered to an agent while the job is running.
//
// IMPORTANT:
//   - New commands should be created using either the [Job.NewCommand] or
//     [JobSummary.NewCommand] method.
//   - New fields should only be of primitive types, slices, or maps, or structs
//     defined in this package. Do not import other internal packages here unless
//     absolutely necessary.
type Command struct {
	// ID is the unique identifier for the command.
	ID string `json:"id"`

	// JobID is the ID of the job this command is associated with.
	JobID string `json:"job_id"`

	// AssignmentID is the ID of the assignment this command is associated with.
	AssignmentID string `json:"assignment_id"`

	// RepoID is the GitHub repository ID the assignment, job, and command are
	// associated with.
	//
	// The value is copied from the job when the command is created, do not set
	// it directly. Persisting the value here enables efficient job and
	// assignment retrieval, creating scoped client tokens, logging, etc.
	RepoID int64 `json:"repo_id"`

	// OwnerID is the GitHub repository's owner ID the assignment, job, and
	// command are associated with.
	//
	// The value is copied from the job when the command is created, do not set
	// it directly. Persisting the value here enables efficient job and
	// assignment retrieval, creating scoped client tokens, logging, etc.
	OwnerID int64 `json:"owner_id"`

	// SessionID is the ID of the session this command is associated with.
	SessionID string `json:"session_id"`

	// ExternalID is the ID of the external command this command represents, for
	// example the session service command ID.
	ExternalID string `json:"external_id"`

	// ActorID is the GitHub user ID for the user associated with this command.
	ActorID int64 `json:"actor_id"`

	// The type of command. Possible values are: "user_message"
	Type Type `json:"type"`

	// Content is the raw command content as provided by the session service.
	Content string `json:"content"`

	// Status is the current status of the command. Possible values are:
	// "pending", "delivered", and "ignored".
	//
	// The initial status for newly created commands is "pending".
	Status Status `json:"status"`

	// ExternalTimestamp is the Unix timestamp when the command was created in
	// the external system, for example the session service.
	//
	// This is set so that we can order commands by their creation time in the
	// external system. If not set, commands will be ordered by their CreatedAt
	// timestamp instead.
	ExternalTimestamp int64 `json:"external_timestamp,omitempty"`

	// CreatedAt is the Unix timestamp when the command was created.
	CreatedAt int64 `json:"created_at"`

	// DeliveredAt is the Unix timestamp when the command was delivered to the
	// agent. This is set when the command status is updated to "delivered".
	// If the command has not been delivered yet, this value will be zero.
	DeliveredAt int64 `json:"delivered_at,omitempty"`

	// UpdatedAt is the Unix timestamp when the command was last updated.
	// This is set by CosmosDB, do not set it directly.
	UpdatedAt int64 `json:"_ts,omitempty"`

	// ETag is the entity tag for the command, used for optimistic concurrency.
	// This is set by CosmosDB, do not set it directly.
	ETag *azcore.ETag `json:"_etag,omitempty"`
}

// Status represents the current status of a command.
type Status string

const (
	// StatusPending indicates the command has been created but not yet
	// delivered to the agent. It is the initial status for newly created commands.
	StatusPending Status = "pending"

	// StatusDelivered indicates the command has been delivered to the agent.
	StatusDelivered Status = "delivered"

	// StatusIgnored indicates the command was ignored because it was received
	// after the job finished, or the command was invalid for some reason.
	StatusIgnored Status = "ignored"
)

type Type string

const (
	// TypeUserMessage represents a message command being submitted by the user
	// which will be delivered to the agent.
	TypeUserMessage Type = "user_message"
)

// NewID generates a new unique identifier for a command.
func NewID() string {
	uid := uuid.New()
	return uid.String()
}

// Timestamp returns the timestamp to use for sorting commands.
// If ExternalTimestamp is set, it will be returned; otherwise, CreatedAt is returned.
func (c *Command) Timestamp() int64 {
	if c.ExternalTimestamp != 0 {
		return c.ExternalTimestamp
	}
	return c.CreatedAt
}
