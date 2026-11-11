package capi

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"sync"
	"testing"
	"time"

	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/joberrors"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/observability"
	"github.com/google/uuid"
	"github.com/stretchr/testify/require"
)

func TestUserClient_PatchSession(t *testing.T) {
	t.Run("successfully patch sessions", func(t *testing.T) {
		callCount := 0
		responses := []PatchSessionsResponse{
			{
				SuccessCount: 2,
				FailureCount: 0,
				Failures:     []PatchFailure{},
			},
		}

		// Create a test HTTP server that simulates the CAPI service
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			require.Equal(t, http.MethodPatch, r.Method)
			require.Equal(t, "/agents/sessions", r.URL.Path)
			require.Equal(t, "application/json", r.Header.Get("Content-Type"))
			require.Equal(t, "123", r.Header.Get("X-GitHub-User"))

			if callCount < len(responses) {
				response := responses[callCount]
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(http.StatusOK)
				json.NewEncoder(w).Encode(response)
			} else {
				w.WriteHeader(http.StatusInternalServerError)
			}
			callCount++
		}))
		defer server.Close()

		// Create a UserClient that points to our test server
		baseURL, err := url.Parse(server.URL)
		require.NoError(t, err)

		obsv := observability.NewNoopExporters()
		client := &UserClient{
			http:    server.Client(),
			baseURL: *baseURL,
			obsv:    obsv,
			userID:  123,
		}

		patches := []SessionPatch{
			{UserID: 123, SessionID: "session-1", ResourceState: "open"},
			{UserID: 123, SessionID: "session-2", ResourceState: "closed"},
		}

		err = client.PatchSessions(context.Background(), patches)

		require.Equal(t, 1, callCount, "Expected number of HTTP calls")
		require.NoError(t, err)
	})
}

func TestSessionClient_ErrorHandlerProvidesDetailedErrors(t *testing.T) {
	t.Run("provides detailed error information when retries are exhausted", func(t *testing.T) {
		attemptCount := 0
		expectedErrorBody := `{"error": "Invalid authentication token", "code": "UNAUTHORIZED"}`

		// Create a test HTTP server that always returns 401 Unauthorized
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			attemptCount++
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusUnauthorized)
			w.Write([]byte(expectedErrorBody))
		}))
		defer server.Close()

		// Create an HmacClient and then a SessionClient that points to our test server
		baseURL, err := url.Parse(server.URL)
		require.NoError(t, err)

		obsv := observability.NewNoopExporters()
		hmacClient := &HmacClient{
			obsv:    obsv,
			baseURL: *baseURL,
			baseTransport: baseTransport{
				RoundTripper:  http.DefaultTransport,
				integrationID: "test-integration",
				ffs:           featureflags.NewNoopClient(nil),
			},
			integrationID: "test-integration",
		}

		// Create a session client with backoff behavior (RetryUnauthorizedErrors: false means 401s are not retried)
		sessionClient := hmacClient.NewSessionClient(123, "invalid-token", SessionClientConfig{
			RetryNotFoundErrors:     false,
			RetryUnauthorizedErrors: false,
		})

		// Attempt to create a session, which should fail without retrying since RetryUnauthorizedErrors is false
		_, err = sessionClient.CreateSession(context.Background(), SessionCreate{
			OwnerID:          123,
			RepoID:           456,
			ResourceID:       789,
			ResourceType:     ResourceTypePullRequest,
			AgentTaskID:      uuid.NewString(),
			EventType:        string(jobs.EventTypePullRequestComment),
			EventURL:         "https://github.com/test/test/pull/789",
			EventIdentifiers: []string{"test-identifier"},
			EventContent:     "@copilot please help",
			State:            SessionStateQueued,
			Name:             "test-session",
		})

		// Verify that an error occurred
		require.Error(t, err)

		// With backoff implementation, unauthorized errors should be treated as permanent when RetryUnauthorizedErrors is false
		require.Equal(t, 1, attemptCount, "Expected only one attempt since 401s are not retried")
		require.ErrorIs(t, err, ErrSessionUnauthorized)
	})
}

func TestMapJobStatusToSessionState(t *testing.T) {
	testCases := []struct {
		jobStatus     jobs.JobStatus
		expectedState SessionState
	}{
		{jobs.JobStatusPending, ""},
		{jobs.JobStatusQueued, SessionStateQueued},
		{jobs.JobStatusRunning, SessionStateInProgress},
		{jobs.JobStatusCompleted, SessionStateCompleted},
		{jobs.JobStatusFailed, SessionStateFailed},
		{jobs.JobStatusCancelled, SessionStateCancelled},
		{jobs.JobStatusTimedOut, SessionStateTimedOut},
	}

	for _, tc := range testCases {
		t.Run(fmt.Sprintf("maps %s to %s", tc.jobStatus, tc.expectedState), func(t *testing.T) {
			result := MapJobStatusToSessionState(tc.jobStatus)
			require.Equal(t, tc.expectedState, result)
		})
	}
}

func TestNewSessionClient_Timeout(t *testing.T) {
	t.Run("uses default timeout on HTTP client", func(t *testing.T) {
		// Override with a shorter timeout for faster test execution
		prevTimeout := DefaultClientTimeout
		t.Cleanup(func() {
			DefaultClientTimeout = prevTimeout
		})
		DefaultClientTimeout = 200 * time.Millisecond

		obsv := observability.NewNoopExporters()
		baseURL, err := url.Parse("https://api.github.com")
		require.NoError(t, err)

		hmacClient := &HmacClient{
			obsv:    obsv,
			baseURL: *baseURL,
			baseTransport: baseTransport{
				RoundTripper:  http.DefaultTransport,
				integrationID: "test-integration",
				ffs:           featureflags.NewNoopClient(nil),
			},
			integrationID: "test-integration",
		}

		sessionClient := hmacClient.NewSessionClient(123, "test-token", SessionClientConfig{
			RetryNotFoundErrors:     false,
			RetryUnauthorizedErrors: false,
		})

		// Access the UserClient to verify it was created
		userClient, ok := sessionClient.(*UserClient)
		require.True(t, ok, "Expected sessionClient to be of type *UserClient")

		// To verify the timeout works, we create a slow server and measure the time it takes to fail
		var once sync.Once
		requestReceived := make(chan struct{})
		done := make(chan struct{})
		slowServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			once.Do(func() {
				close(requestReceived)
			})
			// Block until the test signals completion, exceeding the client timeout
			<-done
			w.WriteHeader(http.StatusOK)
		}))
		defer slowServer.Close()
		defer close(done)

		// Update the baseURL to point to our slow server
		slowURL, err := url.Parse(slowServer.URL)
		require.NoError(t, err)
		userClient.baseURL = *slowURL

		// Attempt to create a session, which should timeout
		ctx, cancel := context.WithTimeout(context.Background(), 500*time.Millisecond)
		defer cancel()

		start := time.Now()
		_, err = userClient.CreateSession(ctx, SessionCreate{
			OwnerID:          123,
			RepoID:           456,
			ResourceID:       789,
			ResourceType:     ResourceTypePullRequest,
			AgentTaskID:      uuid.NewString(),
			EventType:        string(jobs.EventTypePullRequestComment),
			EventURL:         "https://github.com/test/test/pull/789",
			EventIdentifiers: []string{"test-identifier"},
			EventContent:     "@copilot please help",
			State:            SessionStateQueued,
			Name:             "test-session",
		})
		duration := time.Since(start)

		// Verify that an error occurred
		require.Error(t, err)
		// The error should indicate the request failed after retries
		errMsg := err.Error()
		t.Logf("Error message: %s", errMsg)

		// Wait for server to receive request to ensure timeout isn't just a connection issue
		select {
		case <-requestReceived:
			// Good, request was received
		case <-time.After(1 * time.Second):
			t.Fatal("Server never received request")
		}

		// Verify that the timeout occurred within a reasonable time frame
		// The client has a 200ms timeout (overridden), and the context timeout of 500ms limits retries
		require.Less(t, duration, 1*time.Second, "Request should have timed out within 1 second")
		require.Greater(t, duration, 100*time.Millisecond, "Request should have taken at least 100ms (close to the 200ms timeout)")
	})
}

func TestNewSessionClient_ConfigOptions(t *testing.T) {
	obsv := observability.NewNoopExporters()
	baseURL, err := url.Parse("https://api.github.com")
	require.NoError(t, err)

	hmacClient := &HmacClient{
		obsv:    obsv,
		baseURL: *baseURL,
		baseTransport: baseTransport{
			RoundTripper:  http.DefaultTransport,
			integrationID: "test-integration",
			ffs:           featureflags.NewNoopClient(nil),
		},
		integrationID: "test-integration",
	}

	t.Run("creates client with retry config options", func(t *testing.T) {
		config := SessionClientConfig{
			RetryNotFoundErrors:     true,
			RetryUnauthorizedErrors: false,
		}

		sessionClient := hmacClient.NewSessionClient(123, "test-token", config)
		userClient, ok := sessionClient.(*UserClient)
		require.True(t, ok, "Expected sessionClient to be of type *UserClient")

		// Verify the config was set correctly
		require.True(t, userClient.config.RetryNotFoundErrors)
		require.False(t, userClient.config.RetryUnauthorizedErrors)
	})
}

func TestUserClient_DoFunction_BackoffBehavior(t *testing.T) {
	// Override timeout for faster tests
	DefaultClientTimeout = 1 * time.Second
	defer func() { DefaultClientTimeout = 10 * time.Second }()

	obsv := observability.NewNoopExporters()

	t.Run("retries on 404 when RetryNotFoundErrors is true", func(t *testing.T) {
		attemptCount := 0
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			attemptCount++
			if attemptCount < 2 {
				w.WriteHeader(http.StatusNotFound)
			} else {
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(http.StatusOK)
				json.NewEncoder(w).Encode(Session{ID: "test-session"})
			}
		}))
		defer server.Close()

		baseURL, err := url.Parse(server.URL)
		require.NoError(t, err)

		client := &UserClient{
			http:    &http.Client{Timeout: DefaultClientTimeout},
			baseURL: *baseURL,
			obsv:    obsv,
			userID:  123,
			config: SessionClientConfig{
				RetryNotFoundErrors:     true,
				RetryUnauthorizedErrors: false,
			},
		}

		session, err := client.GetSession(context.Background(), "test-session")

		require.NoError(t, err)
		require.NotNil(t, session)
		require.Equal(t, "test-session", session.ID)
		require.Equal(t, 2, attemptCount, "Should have retried once after 404")
	})

	t.Run("does not retry on 404 when RetryNotFoundErrors is false", func(t *testing.T) {
		attemptCount := 0
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			attemptCount++
			w.WriteHeader(http.StatusNotFound)
		}))
		defer server.Close()

		baseURL, err := url.Parse(server.URL)
		require.NoError(t, err)

		client := &UserClient{
			http:    &http.Client{Timeout: DefaultClientTimeout},
			baseURL: *baseURL,
			obsv:    obsv,
			userID:  123,
			config: SessionClientConfig{
				RetryNotFoundErrors:     false,
				RetryUnauthorizedErrors: false,
			},
		}

		_, err = client.GetSession(context.Background(), "test-session")

		require.Error(t, err)
		require.True(t, IsSessionNotFoundError(err))
		require.Equal(t, 1, attemptCount, "Should not have retried on 404")
	})

	t.Run("retries on 401 when RetryUnauthorizedErrors is true", func(t *testing.T) {
		attemptCount := 0
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			attemptCount++
			if attemptCount < 2 {
				w.WriteHeader(http.StatusUnauthorized)
			} else {
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(http.StatusOK)
				json.NewEncoder(w).Encode(Session{ID: "test-session"})
			}
		}))
		defer server.Close()

		baseURL, err := url.Parse(server.URL)
		require.NoError(t, err)

		client := &UserClient{
			http:    &http.Client{Timeout: DefaultClientTimeout},
			baseURL: *baseURL,
			obsv:    obsv,
			userID:  123,
			config: SessionClientConfig{
				RetryNotFoundErrors:     false,
				RetryUnauthorizedErrors: true,
			},
		}

		session, err := client.GetSession(context.Background(), "test-session")

		require.NoError(t, err)
		require.NotNil(t, session)
		require.Equal(t, "test-session", session.ID)
		require.Equal(t, 2, attemptCount, "Should have retried once after 401")
	})

	t.Run("does not retry on 401 when RetryUnauthorizedErrors is false", func(t *testing.T) {
		attemptCount := 0
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			attemptCount++
			w.WriteHeader(http.StatusUnauthorized)
		}))
		defer server.Close()

		baseURL, err := url.Parse(server.URL)
		require.NoError(t, err)

		client := &UserClient{
			http:    &http.Client{Timeout: DefaultClientTimeout},
			baseURL: *baseURL,
			obsv:    obsv,
			userID:  123,
			config: SessionClientConfig{
				RetryNotFoundErrors:     false,
				RetryUnauthorizedErrors: false,
			},
		}

		_, err = client.GetSession(context.Background(), "test-session")

		require.Error(t, err)
		require.True(t, IsSessionUnauthorizedError(err))
		require.Equal(t, 1, attemptCount, "Should not have retried on 401")
	})

	t.Run("does not retry on 429 rate limit errors", func(t *testing.T) {
		attemptCount := 0
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			attemptCount++
			w.WriteHeader(http.StatusTooManyRequests)
		}))
		defer server.Close()

		baseURL, err := url.Parse(server.URL)
		require.NoError(t, err)

		client := &UserClient{
			http:    &http.Client{Timeout: DefaultClientTimeout},
			baseURL: *baseURL,
			obsv:    obsv,
			userID:  123,
			config: SessionClientConfig{
				RetryNotFoundErrors:     false,
				RetryUnauthorizedErrors: false,
			},
		}

		_, err = client.GetSession(context.Background(), "test-session")

		require.Error(t, err)
		require.True(t, IsSessionRateLimitedError(err))
		// 429 errors are currently treated as permanent (non-retryable)
		require.Equal(t, 1, attemptCount, "Should not have retried on 429")
	})

	t.Run("does not retry on non-retryable status codes", func(t *testing.T) {
		testCases := []struct {
			name       string
			statusCode int
		}{
			{"400 Bad Request", http.StatusBadRequest},
			{"403 Forbidden", http.StatusForbidden},
			{"500 Internal Server Error", http.StatusInternalServerError},
		}

		for _, tc := range testCases {
			t.Run(tc.name, func(t *testing.T) {
				attemptCount := 0
				server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
					attemptCount++
					w.WriteHeader(tc.statusCode)
				}))
				defer server.Close()

				baseURL, err := url.Parse(server.URL)
				require.NoError(t, err)

				client := &UserClient{
					http:    &http.Client{Timeout: DefaultClientTimeout},
					baseURL: *baseURL,
					obsv:    obsv,
					userID:  123,
					config: SessionClientConfig{
						RetryNotFoundErrors:     false,
						RetryUnauthorizedErrors: false,
					},
				}

				_, err = client.GetSession(context.Background(), "test-session")

				require.Error(t, err)
				require.Equal(t, 1, attemptCount, "Should not have retried on %d", tc.statusCode)
			})
		}
	})

	t.Run("respects max retries limit", func(t *testing.T) {
		attemptCount := 0
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			attemptCount++
			// Always return 404 to force retries until limit
			w.WriteHeader(http.StatusNotFound)
		}))
		defer server.Close()

		baseURL, err := url.Parse(server.URL)
		require.NoError(t, err)

		client := &UserClient{
			http:    &http.Client{Timeout: DefaultClientTimeout},
			baseURL: *baseURL,
			obsv:    obsv,
			userID:  123,
			config: SessionClientConfig{
				RetryNotFoundErrors:     true,
				RetryUnauthorizedErrors: false,
			},
		}

		_, err = client.GetSession(context.Background(), "test-session")

		require.Error(t, err)
		require.True(t, IsSessionNotFoundError(err))
		// Should attempt DefaultSessionMaxRetries times (currently 3)
		require.Equal(t, DefaultSessionMaxRetries, attemptCount, "Should have attempted max retries")
	})

	t.Run("handles timeout errors with retry", func(t *testing.T) {
		attemptCount := 0
		var once sync.Once
		requestReceived := make(chan struct{})
		done := make(chan struct{})

		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			attemptCount++
			once.Do(func() {
				close(requestReceived)
			})
			// Block until the test signals completion on first attempt to trigger timeout
			if attemptCount < 2 {
				<-done
				return
			}
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusOK)
			json.NewEncoder(w).Encode(Session{ID: "test-session"})
		}))
		defer server.Close()
		defer close(done)

		baseURL, err := url.Parse(server.URL)
		require.NoError(t, err)

		client := &UserClient{
			http:    &http.Client{Timeout: 100 * time.Millisecond},
			baseURL: *baseURL,
			obsv:    obsv,
			userID:  123,
			config: SessionClientConfig{
				RetryNotFoundErrors:     false,
				RetryUnauthorizedErrors: false,
			},
		}

		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()

		session, err := client.GetSession(ctx, "test-session")

		// Wait for first request to be received
		select {
		case <-requestReceived:
			// Good, request was received
		case <-time.After(1 * time.Second):
			t.Fatal("Server never received request")
		}

		// Should eventually succeed after retry
		require.NoError(t, err)
		require.NotNil(t, session)
		require.Greater(t, attemptCount, 1, "Should have retried after timeout")
	})
}

func TestUserClient_DoFunction_ErrorHandling(t *testing.T) {
	obsv := observability.NewNoopExporters()

	t.Run("handles network errors gracefully", func(t *testing.T) {
		// Use an invalid host that will cause a network error
		client := &UserClient{
			http:    &http.Client{Timeout: 100 * time.Millisecond},
			baseURL: url.URL{Scheme: "http", Host: "192.0.2.1:1"}, // TEST-NET-1, reserved and unroutable
			obsv:    obsv,
			userID:  123,
			config: SessionClientConfig{
				RetryNotFoundErrors:     false,
				RetryUnauthorizedErrors: false,
			},
		}

		ctx, cancel := context.WithTimeout(context.Background(), 500*time.Millisecond)
		defer cancel()

		_, err := client.GetSession(ctx, "test-session")

		require.Error(t, err)
		// Should get some kind of network error (connection refused, timeout, etc.)
	})

	t.Run("processes unexpected response correctly", func(t *testing.T) {
		expectedBody := `{"error": "something went wrong"}`
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(http.StatusInternalServerError)
			w.Write([]byte(expectedBody))
		}))
		defer server.Close()

		baseURL, err := url.Parse(server.URL)
		require.NoError(t, err)

		client := &UserClient{
			http:    &http.Client{Timeout: DefaultClientTimeout},
			baseURL: *baseURL,
			obsv:    obsv,
			userID:  123,
			config: SessionClientConfig{
				RetryNotFoundErrors:     false,
				RetryUnauthorizedErrors: false,
			},
		}

		_, err = client.GetSession(context.Background(), "test-session")

		require.Error(t, err)
		var sessionErr *joberrors.SessionResponseError
		require.ErrorAs(t, err, &sessionErr)
		require.Equal(t, http.StatusInternalServerError, sessionErr.StatusCode)
		require.Contains(t, sessionErr.Body, expectedBody)
	})

	t.Run("successfully completes request on 200 OK", func(t *testing.T) {
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusOK)
			json.NewEncoder(w).Encode(Session{
				ID:    "test-session",
				Name:  "Test Session",
				State: SessionStateCompleted,
			})
		}))
		defer server.Close()

		baseURL, err := url.Parse(server.URL)
		require.NoError(t, err)

		client := &UserClient{
			http:    &http.Client{Timeout: DefaultClientTimeout},
			baseURL: *baseURL,
			obsv:    obsv,
			userID:  123,
			config: SessionClientConfig{
				RetryNotFoundErrors:     false,
				RetryUnauthorizedErrors: false,
			},
		}

		session, err := client.GetSession(context.Background(), "test-session")

		require.NoError(t, err)
		require.NotNil(t, session)
		require.Equal(t, "test-session", session.ID)
		require.Equal(t, "Test Session", session.Name)
		require.Equal(t, SessionStateCompleted, session.State)
	})
}

func TestUserClient_RequestBodyRetries(t *testing.T) {
	obsv := observability.NewNoopExporters()

	t.Run("resends request body on retry after 404", func(t *testing.T) {
		attemptCount := 0
		var receivedBodies []string

		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			attemptCount++

			// Read and store the request body
			bodyBytes, err := io.ReadAll(r.Body)
			require.NoError(t, err)
			receivedBodies = append(receivedBodies, string(bodyBytes))

			if attemptCount < 2 {
				w.WriteHeader(http.StatusNotFound)
			} else {
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(http.StatusCreated)
				json.NewEncoder(w).Encode(CreateSessionResponse{ID: "new-session"})
			}
		}))
		defer server.Close()

		baseURL, err := url.Parse(server.URL)
		require.NoError(t, err)

		client := &UserClient{
			http:    &http.Client{Timeout: DefaultClientTimeout},
			baseURL: *baseURL,
			obsv:    obsv,
			userID:  123,
			config: SessionClientConfig{
				RetryNotFoundErrors:     true,
				RetryUnauthorizedErrors: false,
			},
		}

		resp, err := client.CreateSession(context.Background(), SessionCreate{
			OwnerID:          123,
			RepoID:           456,
			ResourceID:       789,
			ResourceType:     ResourceTypePullRequest,
			AgentTaskID:      uuid.NewString(),
			EventType:        string(jobs.EventTypePullRequestComment),
			EventURL:         "https://github.com/test/test/pull/789",
			EventIdentifiers: []string{"test-identifier"},
			EventContent:     "@copilot please help",
			State:            SessionStateQueued,
			Name:             "test-session",
		})

		require.NoError(t, err)
		require.NotNil(t, resp)
		require.Equal(t, "new-session", resp.ID)
		require.Equal(t, 2, attemptCount, "Should have retried once after 404")

		// Verify both requests had the same body
		require.Len(t, receivedBodies, 2)
		require.NotEmpty(t, receivedBodies[0], "First request should have a body")
		require.Equal(t, receivedBodies[0], receivedBodies[1], "Request body should be identical on retry")

		// Verify the body contains expected fields
		var firstBody SessionCreate
		err = json.Unmarshal([]byte(receivedBodies[0]), &firstBody)
		require.NoError(t, err)
		require.Equal(t, uint64(123), firstBody.OwnerID)
		require.Equal(t, uint64(456), firstBody.RepoID)
		require.Equal(t, int64(789), firstBody.ResourceID)
		require.Equal(t, "test-session", firstBody.Name)
	})

	t.Run("resends request body on retry after 401", func(t *testing.T) {
		attemptCount := 0
		var receivedBodies []string

		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			attemptCount++

			// Read and store the request body
			bodyBytes, err := io.ReadAll(r.Body)
			require.NoError(t, err)
			receivedBodies = append(receivedBodies, string(bodyBytes))

			if attemptCount < 2 {
				w.WriteHeader(http.StatusUnauthorized)
			} else {
				w.WriteHeader(http.StatusOK)
			}
		}))
		defer server.Close()

		baseURL, err := url.Parse(server.URL)
		require.NoError(t, err)

		client := &UserClient{
			http:    &http.Client{Timeout: DefaultClientTimeout},
			baseURL: *baseURL,
			obsv:    obsv,
			userID:  123,
			config: SessionClientConfig{
				RetryNotFoundErrors:     false,
				RetryUnauthorizedErrors: true,
			},
		}

		update := SessionUpdate{
			Name:  "updated-session",
			State: SessionStateCompleted,
		}

		err = client.UpdateSession(context.Background(), "test-session", update)

		require.NoError(t, err)
		require.Equal(t, 2, attemptCount, "Should have retried once after 401")

		// Verify both requests had the same body
		require.Len(t, receivedBodies, 2)
		require.NotEmpty(t, receivedBodies[0], "First request should have a body")
		require.Equal(t, receivedBodies[0], receivedBodies[1], "Request body should be identical on retry")

		// Verify the body contains expected fields
		var firstBody SessionUpdate
		err = json.Unmarshal([]byte(receivedBodies[0]), &firstBody)
		require.NoError(t, err)
		require.Equal(t, "updated-session", firstBody.Name)
		require.Equal(t, SessionStateCompleted, firstBody.State)
	})

	t.Run("resends request body on timeout retry", func(t *testing.T) {
		attemptCount := 0
		var receivedBodies []string
		var once sync.Once
		requestReceived := make(chan struct{})
		done := make(chan struct{})

		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			attemptCount++

			// Read and store the request body
			bodyBytes, err := io.ReadAll(r.Body)
			require.NoError(t, err)
			receivedBodies = append(receivedBodies, string(bodyBytes))

			once.Do(func() {
				close(requestReceived)
			})

			if attemptCount < 2 {
				// Block until the test signals completion to trigger timeout
				<-done
				return
			}
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusOK)
			json.NewEncoder(w).Encode(PatchSessionsResponse{
				SuccessCount: 2,
				FailureCount: 0,
			})
		}))
		defer server.Close()
		defer close(done)

		baseURL, err := url.Parse(server.URL)
		require.NoError(t, err)

		client := &UserClient{
			http:    &http.Client{Timeout: 100 * time.Millisecond},
			baseURL: *baseURL,
			obsv:    obsv,
			userID:  123,
			config: SessionClientConfig{
				RetryNotFoundErrors:     false,
				RetryUnauthorizedErrors: false,
			},
		}

		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()

		patches := []SessionPatch{
			{UserID: 123, SessionID: "session-1", ResourceState: "open"},
			{UserID: 123, SessionID: "session-2", ResourceState: "closed"},
		}

		err = client.PatchSessions(ctx, patches)

		// Wait for first request to be received
		select {
		case <-requestReceived:
			// Good, request was received
		case <-time.After(1 * time.Second):
			t.Fatal("Server never received request")
		}

		require.NoError(t, err)
		require.Greater(t, attemptCount, 1, "Should have retried after timeout")

		// Verify both requests had the same body
		require.GreaterOrEqual(t, len(receivedBodies), 2)
		require.NotEmpty(t, receivedBodies[0], "First request should have a body")
		require.Equal(t, receivedBodies[0], receivedBodies[1], "Request body should be identical on retry")

		// Verify the body contains expected fields
		var firstBody PatchSessionsRequest
		err = json.Unmarshal([]byte(receivedBodies[0]), &firstBody)
		require.NoError(t, err)
		require.Len(t, firstBody.Patches, 2)
		require.Equal(t, uint64(123), firstBody.Patches[0].UserID)
		require.Equal(t, "session-1", firstBody.Patches[0].SessionID)
	})

	t.Run("handles requests without body correctly", func(t *testing.T) {
		attemptCount := 0

		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			attemptCount++

			// Verify no body was sent
			bodyBytes, err := io.ReadAll(r.Body)
			require.NoError(t, err)
			require.Empty(t, bodyBytes, "GET request should not have a body")

			if attemptCount < 2 {
				w.WriteHeader(http.StatusNotFound)
			} else {
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(http.StatusOK)
				json.NewEncoder(w).Encode(Session{ID: "test-session"})
			}
		}))
		defer server.Close()

		baseURL, err := url.Parse(server.URL)
		require.NoError(t, err)

		client := &UserClient{
			http:    &http.Client{Timeout: DefaultClientTimeout},
			baseURL: *baseURL,
			obsv:    obsv,
			userID:  123,
			config: SessionClientConfig{
				RetryNotFoundErrors:     true,
				RetryUnauthorizedErrors: false,
			},
		}

		session, err := client.GetSession(context.Background(), "test-session")

		require.NoError(t, err)
		require.NotNil(t, session)
		require.Equal(t, 2, attemptCount, "Should have retried once after 404")
	})

	t.Run("resends large request body on retry", func(t *testing.T) {
		attemptCount := 0
		var receivedBodies []string

		// Create a large event content to ensure body handling works with larger payloads
		largeContent := string(make([]byte, 10000)) // 10KB of data

		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			attemptCount++

			// Read and store the request body
			bodyBytes, err := io.ReadAll(r.Body)
			require.NoError(t, err)
			receivedBodies = append(receivedBodies, string(bodyBytes))

			if attemptCount < 2 {
				w.WriteHeader(http.StatusNotFound)
			} else {
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(http.StatusCreated)
				json.NewEncoder(w).Encode(CreateSessionResponse{ID: "new-session"})
			}
		}))
		defer server.Close()

		baseURL, err := url.Parse(server.URL)
		require.NoError(t, err)

		client := &UserClient{
			http:    &http.Client{Timeout: DefaultClientTimeout},
			baseURL: *baseURL,
			obsv:    obsv,
			userID:  123,
			config: SessionClientConfig{
				RetryNotFoundErrors:     true,
				RetryUnauthorizedErrors: false,
			},
		}

		resp, err := client.CreateSession(context.Background(), SessionCreate{
			OwnerID:          123,
			RepoID:           456,
			ResourceID:       789,
			ResourceType:     ResourceTypePullRequest,
			AgentTaskID:      uuid.NewString(),
			EventType:        string(jobs.EventTypePullRequestComment),
			EventURL:         "https://github.com/test/test/pull/789",
			EventIdentifiers: []string{"test-identifier"},
			EventContent:     largeContent,
			State:            SessionStateQueued,
			Name:             "test-session",
		})

		require.NoError(t, err)
		require.NotNil(t, resp)
		require.Equal(t, 2, attemptCount, "Should have retried once after 404")

		// Verify both requests had the same body
		require.Len(t, receivedBodies, 2)
		require.NotEmpty(t, receivedBodies[0], "First request should have a body")
		require.Equal(t, receivedBodies[0], receivedBodies[1], "Request body should be identical on retry")
		require.Greater(t, len(receivedBodies[0]), 10000, "Body should contain the large content")
	})
}

func TestWithSessionUpdate_ResourceNumber(t *testing.T) {
	session := &Session{
		ID:         "test-session",
		ResourceID: 123,
	}

	resourceType := ResourceTypePullRequest
	session.WithSessionUpdate(&SessionUpdate{
		ResourceType:   &resourceType,
		ResourceID:     999,
		ResourceNumber: 42,
	})

	require.Equal(t, int64(999), session.ResourceID)
	require.Equal(t, 42, session.ResourceNumber)
	require.Equal(t, ResourceTypePullRequest, session.ResourceType)
}

func TestHasUpdate_ResourceNumber(t *testing.T) {
	update := &SessionUpdate{ResourceNumber: 42}
	require.True(t, update.HasUpdate())

	empty := &SessionUpdate{}
	require.False(t, empty.HasUpdate())
}
