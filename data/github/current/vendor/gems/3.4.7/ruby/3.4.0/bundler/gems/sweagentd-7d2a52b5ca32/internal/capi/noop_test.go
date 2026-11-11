package capi

import (
	"context"
	"fmt"
	"sync"
	"testing"

	"github.com/github/sweagentd/internal/jobs"
	"github.com/stretchr/testify/require"
)

// cleanupGlobalSessions clears the global sessions map for testing
func cleanupGlobalSessions() {
	globalSessions.Range(func(key, value interface{}) bool {
		globalSessions.Delete(key)
		return true
	})
}

func TestNoopSessionClient_SingletonPattern(t *testing.T) {
	tests := []struct {
		name         string
		setupClients func() (SessionClient, SessionClient)
		description  string
	}{
		{
			name: "same_noop_client_different_session_clients",
			setupClients: func() (SessionClient, SessionClient) {
				client := &NoopClient{}
				return client.NewSessionClient(123, "token1"), client.NewSessionClient(456, "token2")
			},
			description: "sessions shared between different session clients from same NoopClient",
		},
		{
			name: "different_noop_clients",
			setupClients: func() (SessionClient, SessionClient) {
				client1 := &NoopClient{}
				client2 := &NoopClient{}
				return client1.NewSessionClient(123, "token1"), client2.NewSessionClient(456, "token2")
			},
			description: "sessions shared between session clients from different NoopClient instances",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Clean up any existing sessions from other tests
			cleanupGlobalSessions()

			ctx := context.Background()
			sessionClient1, sessionClient2 := tt.setupClients()

			// Create a session using the first client
			session1Response, err := sessionClient1.CreateSession(
				ctx,
				1,
				2,
				3,
				jobs.EventTypePullRequestComment,
				"http://example.com",
				[]string{"event1"},
				"test event content",
				SessionStateQueued,
				"Test Session 1",
			)
			require.NoError(t, err)
			require.NotNil(t, session1Response)
			sessionID1 := session1Response.ID

			// The session should be accessible from the second client (singleton behavior)
			retrievedSession, err := sessionClient2.GetSession(ctx, sessionID1)
			require.NoError(t, err)
			require.NotNil(t, retrievedSession)
			require.Equal(t, sessionID1, retrievedSession.ID)
			require.Equal(t, "Test Session 1", retrievedSession.Name)

			// Create another session using the second client
			session2Response, err := sessionClient2.CreateSession(
				ctx,
				10,
				20,
				30,
				jobs.EventTypePullRequestComment,
				"http://example2.com",
				[]string{"event2"},
				"test event content 2",
				SessionStateInProgress,
				"Test Session 2",
			)
			require.NoError(t, err)
			require.NotNil(t, session2Response)
			sessionID2 := session2Response.ID

			// The second session should be accessible from the first client (singleton behavior)
			retrievedSession2, err := sessionClient1.GetSession(ctx, sessionID2)
			require.NoError(t, err)
			require.NotNil(t, retrievedSession2)
			require.Equal(t, sessionID2, retrievedSession2.ID)
			require.Equal(t, "Test Session 2", retrievedSession2.Name)

			// Update a session from one client and verify it's updated for the other
			err = sessionClient1.UpdateSession(ctx, sessionID2, SessionUpdate{
				Name:  "Updated Session 2",
				State: SessionStateCompleted,
			})
			require.NoError(t, err)

			// Verify the update is visible from the second client
			updatedSession, err := sessionClient2.GetSession(ctx, sessionID2)
			require.NoError(t, err)
			require.Equal(t, "Updated Session 2", updatedSession.Name)
			require.Equal(t, SessionStateCompleted, updatedSession.State)
		})
	}
}

func TestNoopSessionClient_ConcurrentAccess(t *testing.T) {
	// Clean up any existing sessions from other tests
	cleanupGlobalSessions()

	ctx := context.Background()
	client := &NoopClient{}

	// Test concurrent session creation and access
	const numGoroutines = 10
	const sessionsPerGoroutine = 5

	// Create sessions concurrently
	var wg sync.WaitGroup
	sessionIDs := make([]string, 0, numGoroutines*sessionsPerGoroutine)
	sessionIDsMutex := sync.Mutex{}

	for i := 0; i < numGoroutines; i++ {
		wg.Add(1)
		go func(goroutineID int) {
			defer wg.Done()

			sessionClient := client.NewSessionClient(int64(goroutineID), "token")

			for j := 0; j < sessionsPerGoroutine; j++ {
				sessionResponse, err := sessionClient.CreateSession(
					ctx,
					int64(goroutineID*1000+j), // Unique owner ID
					2,
					3,
					jobs.EventTypePullRequestComment,
					"http://example.com",
					[]string{"event"},
					"test event content",
					SessionStateQueued,
					fmt.Sprintf("Session %d-%d", goroutineID, j),
				)
				require.NoError(t, err)
				require.NotNil(t, sessionResponse)

				sessionIDsMutex.Lock()
				sessionIDs = append(sessionIDs, sessionResponse.ID)
				sessionIDsMutex.Unlock()
			}
		}(i)
	}

	wg.Wait()

	// Verify all sessions can be retrieved from any client
	sessionClient := client.NewSessionClient(999, "token")
	for _, sessionID := range sessionIDs {
		session, err := sessionClient.GetSession(ctx, sessionID)
		require.NoError(t, err)
		require.NotNil(t, session)
		require.Equal(t, sessionID, session.ID)
	}

	// Test concurrent updates
	wg = sync.WaitGroup{}
	for i, sessionID := range sessionIDs[:5] { // Update first 5 sessions
		wg.Add(1)
		go func(id string, index int) {
			defer wg.Done()

			sessionClient := client.NewSessionClient(int64(index+100), "token")
			err := sessionClient.UpdateSession(ctx, id, SessionUpdate{
				Name:  fmt.Sprintf("Updated Session %d", index),
				State: SessionStateCompleted,
			})
			require.NoError(t, err)
		}(sessionID, i)
	}

	wg.Wait()

	// Verify updates are visible
	for i, sessionID := range sessionIDs[:5] {
		session, err := sessionClient.GetSession(ctx, sessionID)
		require.NoError(t, err)
		require.Equal(t, fmt.Sprintf("Updated Session %d", i), session.Name)
		require.Equal(t, SessionStateCompleted, session.State)
	}
}
