package agentcallback

import (
	"time"
)

// AgentUpdateKind represents the kind of update from an agent.
type AgentUpdateKind string

const (
	// AgentUpdateKindProgress represents a generic progress update.
	AgentUpdateKindProgress AgentUpdateKind = "progress"

	// AgentUpdateKindPartialResult represents a partial result update.
	AgentUpdateKindPartialResult AgentUpdateKind = "partialResult"

	// AgentUpdateKindCommentReply represents a message intended for the user.
	AgentUpdateKindCommentReply AgentUpdateKind = "commentReply"

	// AgentUpdateKindResult represents a final result update.
	AgentUpdateKindResult AgentUpdateKind = "result"

	// AgentUpdateKindError represents an error update.
	AgentUpdateKindError AgentUpdateKind = "error"
)

// JobUpdate represents an update from an agent about a job.
type JobUpdate struct {
	JobID               string          `json:"job_id"`
	Kind                AgentUpdateKind `json:"kind"`
	AcceptsUserMessages bool            `json:"accepts_user_messages"`
	CreatedAt           time.Time       `json:"created_at"`
	RepoID              int64           `json:"repo_id"`
	RepoOwnerID         int64           `json:"repo_owner_id"`
	Content             string          `json:"content"` // see runtime/src/types.ts
}
