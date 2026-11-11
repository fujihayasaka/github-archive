package capi

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"slices"
	"time"

	"github.com/cenkalti/backoff/v5"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/joberrors"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
)

// Constants for session-related operations
const (
	CopilotAPIAgentSessions = "copilot_api_agent_sessions"
)

var (
	// ErrSessionNotFound is returned when an attempt is made to access a
	// session and the session service responds with a 404 Not Found.
	ErrSessionNotFound = errors.New("session not found")
	// ErrSessionUnauthorized is returned when an attempt is made to access a
	// session and the session service responds with a 401 Unauthorized.
	ErrSessionUnauthorized = errors.New("unauthorized access to session")
	// ErrSessionRateLimited is returned when an attempt is made to access a
	// session and the session service responds with a 429 Too Many Requests.
	ErrSessionRateLimited = errors.New("session service exceeded rate limit")
)

// IsSessionNotFoundError checks if the given error is due to session not found.
func IsSessionNotFoundError(err error) bool {
	return errors.Is(err, ErrSessionNotFound)
}

// IsSessionUnauthorizedError checks if the given error is due to session unauthorized access.
func IsSessionUnauthorizedError(err error) bool {
	return errors.Is(err, ErrSessionUnauthorized)
}

// IsSessionRateLimitedError checks if the given error is due to session rate limiting.
func IsSessionRateLimitedError(err error) bool {
	return errors.Is(err, ErrSessionRateLimited)
}

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
	ResourceNumber   int                 `json:"resource_number,omitempty"`
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
	WorkflowRunID     uint64             `json:"workflow_run_id"`
	Error             *SessionError      `json:"error"`
	Model             string             `json:"model"`
	AgentTaskID       string             `json:"agent_task_id,omitempty"`
	HeadRef           string             `json:"head_ref,omitempty"`
	BaseRef           string             `json:"base_ref,omitempty"`
	GeneratedPullData *GeneratedPullData `json:"generated_pull_data,omitempty"`
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
	if update.ResourceNumber != 0 {
		s.ResourceNumber = update.ResourceNumber
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
	if update.HeadRef != "" {
		s.HeadRef = update.HeadRef
	}
	if update.BaseRef != "" {
		s.BaseRef = update.BaseRef
	}
	if update.GeneratedPullData != nil {
		s.GeneratedPullData = update.GeneratedPullData
	}

	return s
}

// SessionState represents the state of a session.
type SessionState string

// NewSessionState returns a new session state type.
func NewSessionState(name string) (*SessionState, error) {
	s := SessionState(name)
	if !slices.Contains(allSessionStates, s) {
		return &s, goerrors.Errorf("invalid session state: %s", name)
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
	ResourceNumber   int                 `json:"resource_number,omitzero"`
	ResourceType     SessionResourceType `json:"resource_type,omitempty"`
	EventURL         string              `json:"event_url,omitempty"`
	EventType        string              `json:"event_type,omitempty"`
	EventIdentifiers []string            `json:"event_identifiers,omitempty"`
	EventContent     string              `json:"event_content,omitempty"`
	State            SessionState        `json:"state,omitempty"`
	Model            string              `json:"model,omitempty"`
	AgentTaskID      string              `json:"agent_task_id,omitempty"`
	HeadRef          string              `json:"head_ref,omitempty"`
	BaseRef          string              `json:"base_ref,omitempty"`
}

// SessionUpdate represents the data used to update an existing session.
type SessionUpdate struct {
	Name              string               `json:"name,omitempty"`
	OwnerID           uint64               `json:"owner_id,omitzero"`
	RepoID            uint64               `json:"repo_id,omitzero"`
	ResourceID        int64                `json:"resource_id,omitzero"`
	ResourceNumber    int                  `json:"resource_number,omitzero"`
	ResourceType      *SessionResourceType `json:"resource_type,omitempty"`
	State             SessionState         `json:"state,omitempty"`
	ResourceState     ResourceState        `json:"resource_state,omitempty"`
	WorkflowRunID     uint64               `json:"workflow_run_id,omitzero"`
	Error             *SessionError        `json:"error,omitempty"`
	Model             string               `json:"model,omitempty"`
	HeadRef           string               `json:"head_ref,omitempty"`
	BaseRef           string               `json:"base_ref,omitempty"`
	GeneratedPullData *GeneratedPullData   `json:"generated_pull_data,omitempty"`
}

// HasUpdate returns true if this SessionUpdate contains any non-zero values.
func (sessionUpdate *SessionUpdate) HasUpdate() bool {
	return sessionUpdate.Name != "" ||
		sessionUpdate.OwnerID != 0 ||
		sessionUpdate.RepoID != 0 ||
		sessionUpdate.ResourceID != 0 ||
		sessionUpdate.ResourceNumber != 0 ||
		sessionUpdate.ResourceType != nil ||
		sessionUpdate.State != "" ||
		sessionUpdate.ResourceState != "" ||
		sessionUpdate.WorkflowRunID != 0 ||
		sessionUpdate.Error != nil ||
		sessionUpdate.Model != "" ||
		sessionUpdate.HeadRef != "" ||
		sessionUpdate.BaseRef != "" ||
		sessionUpdate.GeneratedPullData != nil
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

// SessionClientConfig holds configuration options for the SessionClient.
type SessionClientConfig struct {
	// RetryNotFoundErrors indicates whether to retry requests that result in
	// 404 Not Found errors or consider them final.
	RetryNotFoundErrors bool
	// RetryUnauthorizedErrors indicates whether to retry requests that result
	// in 401 Unauthorized errors or consider them final.
	RetryUnauthorizedErrors bool
}

// GeneratedPullData represents pull request metadata generated by the agent that can be used to update the PR title and description.
type GeneratedPullData struct {
	Title       string `json:"title,omitempty"`
	Description string `json:"description,omitempty"`
}

// SessionClient provides methods for managing Copilot agent sessions.
type SessionClient interface {
	CreateSession(ctx context.Context, create SessionCreate) (*CreateSessionResponse, error)
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
func (c *UserClient) CreateSession(ctx context.Context, create SessionCreate) (*CreateSessionResponse, error) {
	ctx, span := c.obsv.Tracer.Start(ctx, "capi.CreateSession")
	defer span.End()

	resourceType := create.ResourceType
	if create.ResourceID == 0 {
		resourceType = ""
	} else if resourceType == "" {
		resourceType = ResourceTypePullRequest
	}
	create.ResourceType = resourceType

	u := "agents/sessions"

	req, err := c.newRequest(ctx, http.MethodPost, u, create)
	if err != nil {
		return nil, err
	}

	resp, err := c.do(ctx, req)
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
		return nil, goerrors.Errorf("failed to decode response: %w", err)
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

	resp, err := c.do(ctx, req)
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

	resp, err := c.do(ctx, req)
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
		return nil, goerrors.Errorf("failed to decode response: %w", err)
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

	resp, err := c.do(ctx, req)
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

	resp, err := c.do(ctx, req)
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
		return goerrors.Errorf("failed to decode patch response: %w", err)
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

func (c *UserClient) listSessions(ctx context.Context, urlStr string) (*ListSessionResponse, error) {
	req, err := c.newRequest(ctx, http.MethodGet, urlStr, nil)
	if err != nil {
		return nil, err
	}

	resp, err := c.do(ctx, req)
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
		return nil, goerrors.Errorf("failed to decode response: %w", err)
	}

	return &listSessionResponse, nil
}

func (c *UserClient) newRequest(ctx context.Context, method, urlStr string, body any) (*http.Request, error) {
	u, err := c.baseURL.Parse(urlStr)
	if err != nil {
		return nil, err
	}

	var bodyBytes []byte
	if body != nil {
		buf := &bytes.Buffer{}
		enc := json.NewEncoder(buf)
		enc.SetEscapeHTML(false)
		err := enc.Encode(body)
		if err != nil {
			return nil, err
		}
		bodyBytes = buf.Bytes()
	}

	var bodyReader io.Reader
	if bodyBytes != nil {
		bodyReader = bytes.NewReader(bodyBytes)
	}

	req, err := http.NewRequestWithContext(ctx, method, u.String(), bodyReader)
	if err != nil {
		return nil, err
	}

	// Set GetBody so the request body can be re-read on retries
	if bodyBytes != nil {
		req.GetBody = func() (io.ReadCloser, error) {
			return io.NopCloser(bytes.NewReader(bodyBytes)), nil
		}
		req.ContentLength = int64(len(bodyBytes))
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

func (c *UserClient) drainAndCloseBody(ctx context.Context, resp *http.Response) {
	defer resp.Body.Close()

	logger := c.obsv.LoggerWithTelemetry(ctx)
	logger.Debug("draining response body to allow connection reuse")

	_, err := io.Copy(io.Discard, resp.Body)
	if err != nil {
		logger.WithError(err).Warn("failed to drain response body")
	}
}

func (c *UserClient) do(ctx context.Context, req *http.Request) (*http.Response, error) {
	ctx, span := c.obsv.Tracer.Start(ctx, "capi.SessionClient.do")
	defer span.End()

	c.obsv.LoggerWithRequestTelemetry(ctx, req).Info("beginning sessions API request with backoff retry strategy")

	// track request retries in context so can include attempt count and backoff
	// duration in telemetry logs
	err := requestctx.AddRequestRetry(ctx, &requestctx.CtxRequestRetry{URL: req.URL})
	if err != nil {
		c.obsv.LogAndReportError(ctx, err, "failed to add request retry to context", observability.WithRequest(req))
	}

	notify := func(err error, next time.Duration) {
		if ri, ok := requestctx.RequestRetry(ctx); ok {
			ri.Backoff = next
		}
		c.obsv.LoggerWithTelemetry(ctx).WithError(err).Warn("error during sessions API request, retrying")
	}

	operation := func() (*http.Response, error) {
		if ri, ok := requestctx.RequestRetry(ctx); ok {
			ri.Attempt++
		}

		logger := c.obsv.LoggerWithRequestTelemetry(ctx, req)
		logger.Info("starting sessions API request")

		// Reset the request body for retry attempts if GetBody is available
		if req.GetBody != nil {
			body, err := req.GetBody()
			if err != nil {
				logger.WithError(err).Warn("failed to reset request body for retry")
				return nil, backoff.Permanent(err)
			}
			req.Body = body
		}

		resp, err := c.http.Do(req)
		if err != nil {
			var urlErr *url.Error

			// Per the net/http docs, any returned error from [http.Client.Do]
			// will be of type [*url.Error], so this should theoretically not
			// reach this condition. But in the case we do, we will not retry.
			if !errors.As(err, &urlErr) {
				logger.WithError(err).Error("error occurred during sessions API request")
				return nil, backoff.Permanent(err)
			}

			switch {
			// Retry on timeout errors since they may be transient, we set a
			// pretty conservative (per-attempt) timeout on the http client,
			// and we set an overall timeout on the backoff retry operation.
			case urlErr.Timeout():
				logger.WithError(err).Warn("timeout error occurred during sessions API request")
				return nil, err

			// Retry on temporary network errors as they are likely transient.
			case urlErr.Temporary():
				logger.WithError(err).Warn("temporary network error occurred during sessions API request")
				return nil, err

			// Do NOT retry on other [url.Error] returned by the [http.Client]
			// and do NOT attempt to read the response body. A non-nil Response
			// is only returned along with non-nil error when CheckRedirect
			// fails, and even in that single case, the returned response body
			// is already closed.
			default:
				logger.WithError(err).Error("non-retryable URL error occurred during sessions API request")
				return nil, backoff.Permanent(err)
			}
		}

		switch resp.StatusCode {
		// We've seen intermittent 401 errors in the past that indicated the
		// provided token didn't exist when attempting to use it. To rule out
		// a race condition between token creation (in the auth service) and
		// its propagation to the session service, we treated these 401
		// responses as potentially transient.
		//
		// This no longer seems to be the case. The vast majority of 401s now
		// appear during session update after having successfully created or
		// retrieved a session. Therefore, we now treat 401s as permanent
		// errors unless the config explicitly opts into retrying them.
		//
		// TODO (colbylwilliams): Re-evaluate this decision if we see a
		// significant number of 401s that appear to be transient.
		case http.StatusUnauthorized:
			err = ErrSessionUnauthorized
			logger.WithError(err).Warn("unauthorized error occurred during sessions API request")

			if c.config.RetryUnauthorizedErrors {
				c.drainAndCloseBody(ctx, resp)
				return nil, err
			}

		// 404 Not Found responses have been historically considered transient
		// and deserving of retries due to:
		//
		//  - The session service's database consistency model, encountering
		//    issues where a recently created session may not be immediately
		//    visible when attempting to retrieve it.
		//  - Propagation delays in the scenario where this service creates a
		//    resource (like a PR) and then immediately attempts to create a
		//    session for that resource.
		//
		// However, with improvements in the session service's consistency model
		// and changes in the workflow and prerequisites for session creation,
		// these scenarios have become less common. As a result, we now treat
		// 404 responses as permanent errors unless the config explicitly opts
		// into retrying them.
		//
		// TODO (colbylwilliams): Re-evaluate this decision if we see a
		// significant number of 404s that appear to be transient.
		case http.StatusNotFound:
			err = ErrSessionNotFound
			logger.WithError(err).Warn("not found error occurred during sessions API request")

			if c.config.RetryNotFoundErrors {
				c.drainAndCloseBody(ctx, resp)
				return nil, err
			}

		// TODO (colbylwilliams):
		// Consider parsing Retry-After header if present and returning a
		// [backoff.RetryAfterError]. However, I need to confirm that the
		// sessions service is actually setting this header appropriately
		// (or at all). We'd also need to determine under what conditions
		// we can trust the server to provide accurate values, and whether
		// those values are small (few seconds). Otherwise, we risk starving
		// our service's resources.
		case http.StatusTooManyRequests:
			err = ErrSessionRateLimited
			logger.WithError(err).Warn("rate limited during sessions API request")

		default:
			// For all other status codes, we consider the request successful
			return resp, nil
		}

		if err != nil {
			// If we have an error at this point, we set it above, but did not
			// choose to retry, so we drain and close the body and return the
			// error wrapped in [backoff.Permanent] to avoid retrying.
			c.drainAndCloseBody(ctx, resp)
			return nil, backoff.Permanent(err)
		}

		return resp, nil
	}

	final, err := backoff.Retry(ctx, operation,
		backoff.WithBackOff(backoff.NewExponentialBackOff()),
		backoff.WithMaxElapsedTime(DefaultSessionMaxElapsedTime),
		backoff.WithMaxTries(DefaultSessionMaxRetries),
		backoff.WithNotify(notify),
	)

	if err != nil {
		return nil, err
	}

	c.obsv.LoggerWithRequestTelemetry(ctx, req).Info("sessions API request completed successfully")

	// clean up request retry info after successful request
	_ = requestctx.AddRequestRetry(ctx, nil)

	return final, nil
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
