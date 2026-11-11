package capi

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"slices"
	"time"

	"github.com/github/sweagentd/internal/joberrors"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/requestctx"
)

// Constants for session-related operations
const (
	CopilotAPIAgentSessions = "copilot_api_agent_sessions"
)

// Session represents a GitHub Copilot agent session.
type Session struct {
	ID               string              `json:"id"`
	Name             string              `json:"name"`
	UserID           uint64              `json:"user_id"`
	AgentID          int64               `json:"agent_id"`
	State            SessionState        `json:"state"`
	OwnerID          uint64              `json:"owner_id"`
	RepoID           uint64              `json:"repo_id"`
	ResourceType     SessionResourceType `json:"resource_type"`
	ResourceID       int64               `json:"resource_id"`
	ResourceState    ResourceState       `json:"resource_state"`
	LastUpdatedAt    time.Time           `json:"last_updated_at,omitzero"`
	CreatedAt        time.Time           `json:"created_at,omitzero"`
	CompletedAt      time.Time           `json:"completed_at,omitzero"`
	EventURL         string              `json:"event_url"`
	EventType        string              `json:"event_type"`
	EventIdentifiers []string            `json:"event_identifiers"`
	EventContent     string              `json:"event_content"`
	// The ID portion in https://github/github/actions/runs/14799761754 for Actions runs.
	// Globally unique and can be used to look up the owner and repo.
	WorkflowRunID uint64        `json:"workflow_run_id"`
	Error         *SessionError `json:"error"`
}

// WithSessionUpdate applies the given update to this session and returns the updated session.
func (s *Session) WithSessionUpdate(update *SessionUpdate) *Session {
	if update.Name != "" {
		s.Name = update.Name
	}
	if update.OwnerID != 0 {
		s.OwnerID = update.OwnerID
	}
	if update.RepoID != 0 {
		s.RepoID = update.RepoID
	}
	if update.ResourceID != 0 {
		s.ResourceID = update.ResourceID
	}
	if update.ResourceType != nil {
		s.ResourceType = *update.ResourceType
	}
	if update.State != "" {
		s.State = update.State
	}
	if update.WorkflowRunID != 0 {
		s.WorkflowRunID = update.WorkflowRunID
	}
	if update.Error != nil {
		s.Error = update.Error
	}

	return s
}

// SessionState represents the state of a session.
type SessionState string

// NewSessionState returns a new session state type.
func NewSessionState(name string) (*SessionState, error) {
	s := SessionState(name)
	if !slices.Contains(allSessionStates, s) {
		return &s, fmt.Errorf("invalid session state: %s", name)
	}

	return &s, nil
}

// IsFinalState checks if a given state is a final state
func IsFinalState(state SessionState) bool {
	return slices.Contains(FinalSessionState, state)
}

// MapJobStatusToSessionState maps a job status to the corresponding session state
func MapJobStatusToSessionState(status jobs.JobStatus) SessionState {
	switch status {
	case jobs.JobStatusQueued:
		return SessionStateQueued
	case jobs.JobStatusRunning:
		return SessionStateInProgress
	case jobs.JobStatusCompleted:
		return SessionStateCompleted
	case jobs.JobStatusCancelled:
		return SessionStateCancelled
	case jobs.JobStatusFailed:
		return SessionStateFailed
	case jobs.JobStatusTimedOut:
		return SessionStateTimedOut
	default:
		return ""
	}
}

var (
	// SessionStateQueued represents the session state when it is queued for processing.
	SessionStateQueued = SessionState("queued")
	// SessionStateInProgress represents the session state when it is in progress.
	SessionStateInProgress = SessionState("in_progress")
	// SessionStateCompleted represents the session state when it has completed.
	SessionStateCompleted = SessionState("completed")
	// SessionStateFailed represents the session state when it has failed.
	SessionStateFailed = SessionState("failed")
	// SessionStateIdle represents the session state when it is idle.
	SessionStateIdle = SessionState("idle")
	// SessionStateWaitingForUser represents the session state when it is waiting for user input.
	SessionStateWaitingForUser = SessionState("waiting_for_user")
	// SessionStateTimedOut represents the session state when it has timed out due to inactivity.
	SessionStateTimedOut = SessionState("timed_out")
	// SessionStateCancelled represents the session state when it has been cancelled.
	SessionStateCancelled = SessionState("cancelled")

	allSessionStates = []SessionState{
		SessionStateQueued,
		SessionStateInProgress,
		SessionStateCompleted,
		SessionStateFailed,
		SessionStateIdle,
		SessionStateWaitingForUser,
		SessionStateTimedOut,
		SessionStateCancelled,
	}

	// FinalSessionState represents the final states of a session.
	FinalSessionState = []SessionState{
		SessionStateCompleted,
		SessionStateFailed,
		SessionStateTimedOut,
		SessionStateCancelled,
	}
)

// SessionResourceType represents the type of resource associated with a session.
type SessionResourceType string

// Resource types for sessions
const (
	ResourceTypePullRequest SessionResourceType = "pull"
	ResourceTypeIssue       SessionResourceType = "issue"
)

// ResourceState represents the state of a resource.
type ResourceState string

const (
	// ResourceStateDraft represents the resource state when it is draft.
	ResourceStateDraft = ResourceState("draft")
	// ResourceStateOpen represents the resource state when it is open.
	ResourceStateOpen = ResourceState("open")
	// ResourceStateMerged represents the resource state when it has been merged.
	ResourceStateMerged = ResourceState("merged")
	// ResourceStateClosed represents the resource state when it has been closed.
	ResourceStateClosed = ResourceState("closed")
)

// SessionError represents an error that occurred during session operations.
type SessionError struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

// SessionCreate represents the data needed to create a new session.
type SessionCreate struct {
	Name             string              `json:"name,omitempty"`
	OwnerID          uint64              `json:"owner_id,omitzero"`
	RepoID           uint64              `json:"repo_id,omitzero"`
	ResourceID       int64               `json:"resource_id,omitzero"`
	ResourceType     SessionResourceType `json:"resource_type,omitempty"`
	EventURL         string              `json:"event_url,omitempty"`
	EventType        string              `json:"event_type,omitempty"`
	EventIdentifiers []string            `json:"event_identifiers,omitempty"`
	EventContent     string              `json:"event_content,omitempty"`
	State            SessionState        `json:"state,omitempty"`
}

// SessionUpdate represents the data used to update an existing session.
type SessionUpdate struct {
	Name          string               `json:"name,omitempty"`
	OwnerID       uint64               `json:"owner_id,omitzero"`
	RepoID        uint64               `json:"repo_id,omitzero"`
	ResourceID    int64                `json:"resource_id,omitzero"`
	ResourceType  *SessionResourceType `json:"resource_type,omitempty"`
	State         SessionState         `json:"state,omitempty"`
	ResourceState ResourceState        `json:"resource_state,omitempty"`
	WorkflowRunID uint64               `json:"workflow_run_id,omitzero"`
	Error         *SessionError        `json:"error,omitempty"`
}

// HasUpdate returns true if this SessionUpdate contains any non-zero values.
func (sessionUpdate *SessionUpdate) HasUpdate() bool {
	return sessionUpdate.Name != "" ||
		sessionUpdate.OwnerID != 0 ||
		sessionUpdate.RepoID != 0 ||
		sessionUpdate.ResourceID != 0 ||
		sessionUpdate.ResourceType != nil ||
		sessionUpdate.State != "" ||
		sessionUpdate.ResourceState != "" ||
		sessionUpdate.WorkflowRunID != 0 ||
		sessionUpdate.Error != nil
}

// SessionPatch represents a patch operation to update session state.
type SessionPatch struct {
	UserID        uint64 `json:"user_id"                  validate:"required"`
	SessionID     string `json:"session_id"               validate:"required"`
	ResourceState string `json:"resource_state,omitempty" validate:"oneof=draft open closed merged"`
}

// PatchFailure represents a failure in a patch operation.
type PatchFailure struct {
	SessionID string `json:"session_id"`
	Error     string `json:"error"`
	ErrorType string `json:"error_type"`
}

// PatchSessionsRequest represents a request to patch multiple sessions.
type PatchSessionsRequest struct {
	Patches []SessionPatch `json:"patches"`
}

// PatchSessionsResponse represents the response from a patch sessions operation.
type PatchSessionsResponse struct {
	SuccessCount int            `json:"success_count"`
	FailureCount int            `json:"failure_count"`
	Failures     []PatchFailure `json:"failures,omitempty"`
}

// CreateSessionResponse represents the response from creating a session.
type CreateSessionResponse struct {
	ID string `json:"id"`
}

// ListSessionResponse represents the response from listing sessions.
type ListSessionResponse struct {
	Sessions []Session `json:"sessions"`
}

// SessionClient provides methods for managing Copilot agent sessions.
type SessionClient interface {
	CreateSession(ctx context.Context, ownerID, repoID, pullID int64, eventType jobs.EventType, eventURL string, eventIdentifiers []string, eventContent string, sessionState SessionState, sessionName string) (*CreateSessionResponse, error)
	UpdateSession(ctx context.Context, sessionID string, update SessionUpdate) error
	GetSession(ctx context.Context, sessionID string) (*Session, error)
	ListSessions(ctx context.Context, ownerID, repoID int64) (*ListSessionResponse, error)
	ListSessionsByRepoID(ctx context.Context, repoID int64) (*ListSessionResponse, error)
	ListSessionsByRepoNWO(ctx context.Context, owner, repo string) (*ListSessionResponse, error)
	ListSessionsByResourceID(ctx context.Context, resourceType string, resourceID int64) (*ListSessionResponse, error)
	UpdateSessionLogs(ctx context.Context, sessionID, logs string) error
	PatchSessions(ctx context.Context, patches []SessionPatch) error
}

var _ SessionClient = &UserClient{}

// CreateSession creates a new session for the authenticated user.
func (c *UserClient) CreateSession(ctx context.Context, ownerID, repoID, pullID int64, eventType jobs.EventType, eventURL string, eventIdentifiers []string, eventContent string, sessionState SessionState, sessionName string) (*CreateSessionResponse, error) {
	ctx, span := c.obsv.Tracer.Start(ctx, "capi.CreateSession")
	defer span.End()
	resourceType := ResourceTypePullRequest
	if pullID == 0 {
		resourceType = ""
	}

	u := "agents/sessions"

	body := SessionCreate{
		OwnerID:          uint64(ownerID),
		RepoID:           uint64(repoID),
		ResourceID:       pullID,
		ResourceType:     resourceType,
		EventURL:         eventURL,
		EventType:        string(eventType),
		EventIdentifiers: eventIdentifiers,
		EventContent:     eventContent,
		State:            sessionState,
	}

	if sessionName != "" {
		body.Name = sessionName
	}

	req, err := c.newRequest(ctx, http.MethodPost, u, body)
	if err != nil {
		return nil, err
	}

	req = req.WithContext(ctx)
	resp, err := c.http.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusCreated {
		return nil, c.processUnexpectedResponse(ctx, resp)
	}

	var createSessionResponse CreateSessionResponse
	err = json.NewDecoder(resp.Body).Decode(&createSessionResponse)
	if err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	return &createSessionResponse, nil
}

// UpdateSession updates a session
func (c *UserClient) UpdateSession(ctx context.Context, sessionID string, update SessionUpdate) error {
	ctx, span := c.obsv.Tracer.Start(ctx, "capi.UpdateSession")
	defer span.End()

	u := fmt.Sprintf("agents/sessions/%s", sessionID)
	req, err := c.newRequest(ctx, http.MethodPut, u, update)
	if err != nil {
		return err
	}

	req = req.WithContext(ctx)
	resp, err := c.http.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return c.processUnexpectedResponse(ctx, resp)
	}

	return nil
}

// GetSession retrieves a session by its ID.
func (c *UserClient) GetSession(ctx context.Context, sessionID string) (*Session, error) {
	ctx, span := c.obsv.Tracer.Start(ctx, "capi.GetSession")
	defer span.End()

	u := fmt.Sprintf("agents/sessions/%s", sessionID)
	req, err := c.newRequest(ctx, http.MethodGet, u, nil)
	if err != nil {
		return nil, err
	}

	req = req.WithContext(ctx)
	resp, err := c.http.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, c.processUnexpectedResponse(ctx, resp)
	}

	var session Session
	err = json.NewDecoder(resp.Body).Decode(&session)
	if err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	return &session, nil
}

// ListSessions retrieves all sessions for the authenticated user.
func (c *UserClient) ListSessions(ctx context.Context, ownerID, repoID int64) (*ListSessionResponse, error) {
	ctx, span := c.obsv.Tracer.Start(ctx, "capi.ListSessions")
	defer span.End()

	u := "agents/sessions"
	return c.listSessions(ctx, u)
}

// ListSessionsByRepoID returns a session by its Repo ID
func (c *UserClient) ListSessionsByRepoID(ctx context.Context, repoID int64) (*ListSessionResponse, error) {
	ctx, span := c.obsv.Tracer.Start(ctx, "capi.ListSessionsByRepoID")
	defer span.End()

	u := fmt.Sprintf("agents/sessions/repo/%d", repoID)
	return c.listSessions(ctx, u)
}

// ListSessionsByRepoNWO returns a session by Namespace With Owner
func (c *UserClient) ListSessionsByRepoNWO(ctx context.Context, owner, repo string) (*ListSessionResponse, error) {
	ctx, span := c.obsv.Tracer.Start(ctx, "capi.ListSessionsByRepoNWO")
	defer span.End()

	u := fmt.Sprintf("agents/sessions/nwo/%s/%s", owner, repo)
	return c.listSessions(ctx, u)
}

// ListSessionsByResourceID returns all session of a specific resource id in a repo
func (c *UserClient) ListSessionsByResourceID(ctx context.Context, resourceType string, resourceID int64) (*ListSessionResponse, error) {
	ctx, span := c.obsv.Tracer.Start(ctx, "capi.ListSessionsByResourceID")
	defer span.End()

	u := fmt.Sprintf("agents/sessions/resource/%s/%d", resourceType, resourceID)
	return c.listSessions(ctx, u)
}

// UpdateSessionLogs updates a session logs by its ID
func (c *UserClient) UpdateSessionLogs(ctx context.Context, sessionID, logs string) error {
	ctx, span := c.obsv.Tracer.Start(ctx, "capi.UpdateSessionLogs")
	defer span.End()

	u := fmt.Sprintf("agents/sessions/%s/logs", sessionID)
	req, err := c.newRequest(ctx, http.MethodPut, u, logs)
	if err != nil {
		return err
	}

	req = req.WithContext(ctx)
	resp, err := c.http.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return c.processUnexpectedResponse(ctx, resp)
	}

	return nil
}

// PatchSessions patches select fields for multiple sessions in a single request
func (c *UserClient) PatchSessions(ctx context.Context, patches []SessionPatch) error {
	ctx, span := c.obsv.Tracer.Start(ctx, "capi.PatchSessions")
	defer span.End()

	req, err := c.newRequest(ctx, http.MethodPatch, "agents/sessions", PatchSessionsRequest{Patches: patches})
	if err != nil {
		return err
	}

	req = req.WithContext(ctx)
	resp, err := c.http.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return c.processUnexpectedResponse(ctx, resp)
	}

	var response PatchSessionsResponse
	err = json.NewDecoder(resp.Body).Decode(&response)
	if err != nil {
		return fmt.Errorf("failed to decode patch response: %w", err)
	}

	if response.FailureCount == 0 {
		return nil
	}

	b, err := json.Marshal(response.Failures)
	if err == nil {
		c.obsv.Logger.Warn(fmt.Sprintf("patch session request results in failures: %s", string(b)))
	}

	return nil
}

func (c *UserClient) listSessions(ctx context.Context, url string) (*ListSessionResponse, error) {
	req, err := c.newRequest(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}

	req = req.WithContext(ctx)
	resp, err := c.http.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, c.processUnexpectedResponse(ctx, resp)
	}

	var listSessionResponse ListSessionResponse
	err = json.NewDecoder(resp.Body).Decode(&listSessionResponse)
	if err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	return &listSessionResponse, nil
}

func (c *UserClient) newRequest(ctx context.Context, method, urlStr string, body any) (*http.Request, error) {
	u, err := c.baseURL.Parse(urlStr)
	if err != nil {
		return nil, err
	}

	var buf io.ReadWriter
	if body != nil {
		buf = &bytes.Buffer{}
		enc := json.NewEncoder(buf)
		enc.SetEscapeHTML(false)
		err := enc.Encode(body)
		if err != nil {
			return nil, err
		}
	}

	req, err := http.NewRequestWithContext(ctx, method, u.String(), buf)
	if err != nil {
		return nil, err
	}

	job, ok := requestctx.Job(ctx)
	if ok {
		req.Header.Set(InteractionIDHeader, job.ID)
	}

	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}

	req.Header.Set(GitHubUserIDHeader, fmt.Sprintf("%d", c.userID))

	return req, nil
}

func (c *UserClient) processUnexpectedResponse(ctx context.Context, resp *http.Response) error {
	bodyBytes, err := io.ReadAll(resp.Body)
	if err != nil {
		c.obsv.LoggerWithTelemetry(ctx).Error(fmt.Sprintf("failed to read response body: %v", err))
	}
	err = &joberrors.SessionResponseError{
		StatusCode: resp.StatusCode,
		Body:       string(bodyBytes),
	}
	c.obsv.LoggerWithTelemetry(ctx).Error(err.Error())
	return err
}
