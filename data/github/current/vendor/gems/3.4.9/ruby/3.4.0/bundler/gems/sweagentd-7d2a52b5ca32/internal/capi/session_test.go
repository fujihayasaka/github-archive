package capi

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"net/url"
	"sync"
	"testing"
	"time"

	"github.com/github/sweagentd/internal/joberrors"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/observability"
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
			},
			integrationID: "test-integration",
		}

		sessionClient := hmacClient.NewSessionClient(123, "invalid-token")

		// Attempt to create a session, which should fail and exhaust retries
		_, err = sessionClient.CreateSession(
			context.Background(),
			123,                                     // ownerID
			456,                                     // repoID
			789,                                     // pullID
			jobs.EventTypePullRequestComment,        // eventType
			"https://github.com/test/test/pull/789", // eventURL
			[]string{"test-identifier"},             // eventIdentifiers
			"@copilot please help",                  // eventContent
			SessionStateQueued,                      // sessionState
			"test-session",                          // sessionName
		)

		// Verify that an error occurred
		require.Error(t, err)
		var sessionErr *joberrors.SessionResponseError
		if !errors.As(err, &sessionErr) {
			require.Fail(t, "Expected error to be of type SessionResponseError")
			return
		}
		require.Equal(t, http.StatusUnauthorized, sessionErr.StatusCode)
		require.Equal(t, fmt.Sprintf("session API request failed after %d attempts: %s", attemptCount, expectedErrorBody), sessionErr.Body)

		// Verify that the error message contains detailed information
		errorMsg := err.Error()
		t.Logf("Error message: %s", errorMsg)

		// The error should mention the number of attempts, status code, and response body
		require.Contains(t, errorMsg, "session API request failed after")
		require.Contains(t, errorMsg, "attempts")
		require.Contains(t, errorMsg, "unexpected status code 401")
		require.Contains(t, errorMsg, expectedErrorBody)

		// Verify that multiple attempts were made (retryable client should retry 401s based on CheckRetry function)
		require.Greater(t, attemptCount, 1, "Expected multiple retry attempts")
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
		// Override with a shorter timeout for faster test execution (1 second instead of 10)
		DefaultSessionTimeout = 1 * time.Second

		obsv := observability.NewNoopExporters()
		baseURL, err := url.Parse("https://api.github.com")
		require.NoError(t, err)

		hmacClient := &HmacClient{
			obsv:    obsv,
			baseURL: *baseURL,
			baseTransport: baseTransport{
				RoundTripper:  http.DefaultTransport,
				integrationID: "test-integration",
			},
			integrationID: "test-integration",
		}

		sessionClient := hmacClient.NewSessionClient(123, "test-token")

		// Access the UserClient to verify it was created
		userClient, ok := sessionClient.(*UserClient)
		require.True(t, ok, "Expected sessionClient to be of type *UserClient")

		// The http client returned by StandardClient() wraps the retryablehttp client
		// To verify the timeout works, we create a slow server and measure the time it takes to fail
		var once sync.Once
		requestReceived := make(chan struct{})
		slowServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			once.Do(func() {
				close(requestReceived)
			})
			// Sleep for 5 seconds to exceed the overridden timeout (1 second)
			time.Sleep(5 * time.Second)
			w.WriteHeader(http.StatusOK)
		}))
		defer slowServer.Close()

		// Update the baseURL to point to our slow server
		slowURL, err := url.Parse(slowServer.URL)
		require.NoError(t, err)
		userClient.baseURL = *slowURL

		// Attempt to create a session, which should timeout
		// Use a context with a short timeout to make the test run faster
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()

		start := time.Now()
		_, err = userClient.CreateSession(
			ctx,
			123,                                     // ownerID
			456,                                     // repoID
			789,                                     // pullID
			jobs.EventTypePullRequestComment,        // eventType
			"https://github.com/test/test/pull/789", // eventURL
			[]string{"test-identifier"},             // eventIdentifiers
			"@copilot please help",                  // eventContent
			SessionStateQueued,                      // sessionState
			"test-session",                          // sessionName
		)
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
		case <-time.After(2 * time.Second):
			t.Fatal("Server never received request")
		}

		// Verify that the timeout occurred within a reasonable time frame
		// The client has a 1 second timeout (overridden), and the context timeout of 2 seconds limits retries
		// We expect the test to complete in under 3 seconds
		require.Less(t, duration, 3*time.Second, "Request should have timed out within 3 seconds")
		// The first request should timeout after ~1 second
		require.Greater(t, duration, 800*time.Millisecond, "Request should have taken at least 800ms (close to the 1s timeout)")
	})
}
