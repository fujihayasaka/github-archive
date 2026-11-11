package capi

import (
	"context"
	"errors"
	"fmt"
	"sync"
	"time"

	"github.com/github/sweagentd/internal/jobs"
	"github.com/google/uuid"
	"github.com/openai/openai-go"
)

// Global singleton session storage for all NoopSessionClient instances
var globalSessions sync.Map // map[string]Session where key is session ID

// NoopClient is a no-operation implementation of the Client interface for testing.
type NoopClient struct {
	MockChatCompletions func(ctx context.Context, userID, interactionID string, body *openai.ChatCompletionNewParams) (*openai.ChatCompletion, error)
	MockCreateSession   func(ctx context.Context, ownerID, repoID, pullID int64, eventType jobs.EventType, eventURL string, eventIdentifiers []string, eventContent string, sessionState SessionState, sessionName string) (*CreateSessionResponse, error)
	MockGetSession      func(ctx context.Context, sessionID string) (*Session, error)
	MockUpdateSession   func(ctx context.Context, sessionID string, update SessionUpdate) error
	MockPatchSessions   func(ctx context.Context, patches []SessionPatch) error
}

// NoopSessionClient is a no-operation implementation of the SessionClient interface for testing.
type NoopSessionClient struct {
	MockCreateSession func(ctx context.Context, ownerID, repoID, pullID int64, eventType jobs.EventType, eventURL string, eventIdentifiers []string, eventContent string, sessionState SessionState, sessionName string) (*CreateSessionResponse, error)
	MockGetSession    func(ctx context.Context, sessionID string) (*Session, error)
	MockUpdateSession func(ctx context.Context, sessionID string, update SessionUpdate) error
	MockPatchSessions func(ctx context.Context, patches []SessionPatch) error
}

var _ Client = &NoopClient{}
var _ SessionClient = &NoopSessionClient{}

// NewNoopClient creates a new noop CAPI client.
func NewNoopClient() *NoopClient {
	return &NoopClient{
		MockChatCompletions: nil,
		MockCreateSession:   nil,
		MockGetSession:      nil,
		MockUpdateSession:   nil,
	}
}

// NewSessionClient creates a new noop session client.
func (c *NoopClient) NewSessionClient(userID int64, token string) SessionClient {
	return &NoopSessionClient{
		MockCreateSession: c.MockCreateSession,
		MockGetSession:    c.MockGetSession,
		MockUpdateSession: c.MockUpdateSession,
		MockPatchSessions: c.MockPatchSessions,
	}
}

// ChatCompletions provides a mock implementation of chat completions.
func (c *NoopClient) ChatCompletions(ctx context.Context, userID, interactionID string, body *openai.ChatCompletionNewParams) (*openai.ChatCompletion, error) {
	if c.MockChatCompletions != nil {
		return c.MockChatCompletions(ctx, userID, interactionID, body)
	}

	return &openai.ChatCompletion{
		ID: "noop",
		Choices: []openai.ChatCompletionChoice{
			{
				Message: openai.ChatCompletionMessage{
					Role:    "assistant",
					Content: "I'm sorry, I cannot do that, Dave.",
				},
			},
		},
	}, nil
}

// CreateSession creates a new session with the given parameters for testing purposes.
func (c *NoopSessionClient) CreateSession(ctx context.Context, ownerID, repoID, pullID int64, eventType jobs.EventType, eventURL string, eventIdentifiers []string, eventContent string, sessionState SessionState, sessionName string) (*CreateSessionResponse, error) {
	if c.MockCreateSession != nil {
		return c.MockCreateSession(ctx, ownerID, repoID, pullID, eventType, eventURL, eventIdentifiers, eventContent, sessionState, sessionName)
	}

	session := &Session{
		ID:               uuid.New().String(),
		Name:             sessionName,
		OwnerID:          uint64(ownerID),
		RepoID:           uint64(repoID),
		ResourceID:       pullID,
		ResourceType:     "pull",
		EventType:        string(eventType),
		EventURL:         eventURL,
		EventIdentifiers: eventIdentifiers,
		EventContent:     eventContent,
		State:            sessionState,
		CreatedAt:        time.Now(),
		LastUpdatedAt:    time.Now(),
	}

	// Check if session already exists using the global map
	if _, exists := globalSessions.Load(session.ID); exists {
		return nil, fmt.Errorf("session already exists: %s", session.ID)
	}

	// Store the session in the global map
	globalSessions.Store(session.ID, *session)
	return &CreateSessionResponse{ID: session.ID}, nil
}

// GetSession retrieves a session by its ID for testing purposes.
func (c *NoopSessionClient) GetSession(ctx context.Context, sessionID string) (*Session, error) {
	if c.MockGetSession != nil {
		return c.MockGetSession(ctx, sessionID)
	}

	// Load session from the global map
	if value, exists := globalSessions.Load(sessionID); exists {
		session, ok := value.(Session)
		if !ok {
			return nil, errors.New("value is not session")
		}

		return &session, nil
	}
	return nil, fmt.Errorf("session not found: %s", sessionID)
}

// ListSessions returns a list of sessions for the given owner and repo for testing purposes.
func (c *NoopSessionClient) ListSessions(ctx context.Context, ownerID, repoID int64) (*ListSessionResponse, error) {
	return nil, nil
}

// ListSessionsByRepoID returns a list of sessions for the given repo ID for testing purposes.
func (c *NoopSessionClient) ListSessionsByRepoID(ctx context.Context, repoID int64) (*ListSessionResponse, error) {
	return nil, nil
}

// ListSessionsByRepoNWO returns a list of sessions for the given repo name and owner for testing purposes.
func (c *NoopSessionClient) ListSessionsByRepoNWO(ctx context.Context, owner, repo string) (*ListSessionResponse, error) {
	return nil, nil
}

// ListSessionsByResourceID returns a list of sessions for the given resource type and ID for testing purposes.
func (c *NoopSessionClient) ListSessionsByResourceID(ctx context.Context, resourceType string, resourceID int64) (*ListSessionResponse, error) {
	return nil, nil
}

// UpdateSession updates the specified session with the provided update data for testing purposes.
func (c *NoopSessionClient) UpdateSession(ctx context.Context, sessionID string, update SessionUpdate) error {
	if c.MockUpdateSession != nil {
		return c.MockUpdateSession(ctx, sessionID, update)
	}

	// Load session from the global map
	if value, exists := globalSessions.Load(sessionID); exists {
		session, ok := value.(Session)
		if !ok {
			return errors.New("value is not session")
		}
		// Update the session fields
		if update.Name != "" {
			session.Name = update.Name
		}
		if update.State != "" {
			session.State = update.State
		}
		if update.WorkflowRunID != 0 {
			session.WorkflowRunID = update.WorkflowRunID
		}
		if update.Error != nil {
			session.Error = update.Error
		}
		session.LastUpdatedAt = time.Now()

		// Store the updated session back to the global map
		globalSessions.Store(sessionID, session)
		return nil
	}

	return fmt.Errorf("session not found: %s", sessionID)
}

// UpdateSessionLogs updates the logs for the specified session for testing purposes.
func (c *NoopSessionClient) UpdateSessionLogs(ctx context.Context, sessionID, logs string) error {
	return nil
}

// PatchSessions applies patches to multiple sessions for testing purposes.
func (c *NoopSessionClient) PatchSessions(ctx context.Context, patches []SessionPatch) error {
	if c.MockPatchSessions != nil {
		return c.MockPatchSessions(ctx, patches)
	}
	return nil
}
