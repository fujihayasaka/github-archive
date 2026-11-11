package capi

import (
	"context"
	"sync"
	"time"

	"github.com/github/sweagentd/internal/goerrors"
	"github.com/google/uuid"
	"github.com/openai/openai-go"
)

// Global singleton session storage for all NoopSessionClient instances
var globalSessions sync.Map // map[string]Session where key is session ID

// NoopClient is a no-operation implementation of the Client interface for testing.
type NoopClient struct {
	MockChatCompletions       func(ctx context.Context, userID, interactionID string, body *openai.ChatCompletionNewParams) (*openai.ChatCompletion, error)
	MockCreateSession         func(ctx context.Context, create SessionCreate) (*CreateSessionResponse, error)
	MockGetSession            func(ctx context.Context, sessionID string) (*Session, error)
	MockUpdateSession         func(ctx context.Context, sessionID string, update SessionUpdate) error
	MockPatchSessions         func(ctx context.Context, patches []SessionPatch) error
	MockListCodingAgentModels func(ctx context.Context, userID uint64) ([]Model, error)
}

// NoopSessionClient is a no-operation implementation of the SessionClient interface for testing.
type NoopSessionClient struct {
	MockCreateSession func(ctx context.Context, create SessionCreate) (*CreateSessionResponse, error)
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
func (c *NoopClient) NewSessionClient(userID int64, token string, config SessionClientConfig) SessionClient {
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

// ListCodingAgentModels returns a mock list of models for testing purposes.
func (c *NoopClient) ListCodingAgentModels(ctx context.Context, userID uint64) ([]Model, error) {
	if c.MockListCodingAgentModels != nil {
		return c.MockListCodingAgentModels(ctx, userID)
	}
	return []Model{
		{
			ID:     "noop-model-1",
			Object: "model",
		},
	}, nil
}

// CreateSession creates a new session with the given parameters for testing purposes.
func (c *NoopSessionClient) CreateSession(ctx context.Context, create SessionCreate) (*CreateSessionResponse, error) {
	if c.MockCreateSession != nil {
		return c.MockCreateSession(ctx, create)
	}

	resourceType := create.ResourceType
	if create.ResourceID == 0 {
		resourceType = ""
	} else if resourceType == "" {
		resourceType = ResourceTypePullRequest
	}

	session := &Session{
		ID:               uuid.New().String(),
		Name:             create.Name,
		OwnerID:          create.OwnerID,
		RepoID:           create.RepoID,
		ResourceID:       create.ResourceID,
		ResourceType:     resourceType,
		EventType:        create.EventType,
		EventURL:         create.EventURL,
		EventIdentifiers: create.EventIdentifiers,
		EventContent:     create.EventContent,
		State:            create.State,
		CreatedAt:        time.Now(),
		LastUpdatedAt:    time.Now(),
		Model:            create.Model,
		HeadRef:          create.HeadRef,
		BaseRef:          create.BaseRef,
	}

	// Check if session already exists using the global map
	if _, exists := globalSessions.Load(session.ID); exists {
		return nil, goerrors.Errorf("session already exists: %s", session.ID)
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
			return nil, goerrors.New("value is not session")
		}

		return &session, nil
	}
	return nil, goerrors.Errorf("session not found: %s", sessionID)
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
			return goerrors.New("value is not session")
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
		if update.HeadRef != "" {
			session.HeadRef = update.HeadRef
		}
		if update.BaseRef != "" {
			session.BaseRef = update.BaseRef
		}
		session.LastUpdatedAt = time.Now()

		// Store the updated session back to the global map
		globalSessions.Store(sessionID, session)
		return nil
	}

	return goerrors.Errorf("session not found: %s", sessionID)
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
