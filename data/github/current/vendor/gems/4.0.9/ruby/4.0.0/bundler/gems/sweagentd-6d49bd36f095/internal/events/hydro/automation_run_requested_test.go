package hydro

import (
	"context"
	"testing"
	"time"

	automationsv0 "github.com/github/hydro-schemas-go/hydro/schemas/copilot_mission_control/v0"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/proto"
)

func TestGetAutomationRunRequestedEvent(t *testing.T) {
	t.Run("maps all routing fields from proto", func(t *testing.T) {
		ts := time.Date(2025, 6, 15, 10, 30, 0, 0, time.UTC)

		msg := &automationsv0.AutomationRunRequested{
			AutomationId: "auto-123",
			Event:        "workflow_run",
			Type:         "completed",
			ResourceUrl:  "/org/repo/actions/runs/999",
			OwnerLogin:   "org",
			RepoName:     "repo",
			RepoId:       100,
			OwnerId:      200,
			UserId:       300,
			UserLogin:    "user-login",
			Conclusion:   "failure",
		}

		data, err := proto.Marshal(msg)
		require.NoError(t, err)

		protoMsg, event, err := getAutomationRunRequestedEvent(context.Background(), data, ts, nil)
		require.NoError(t, err)
		require.NotNil(t, protoMsg)
		require.NotNil(t, event)

		assert.Equal(t, "auto-123", event.AutomationID)
		assert.Equal(t, "workflow_run", event.Event)
		assert.Equal(t, "completed", event.Type)
		assert.Equal(t, "/org/repo/actions/runs/999", event.ResourceURL)
		assert.Equal(t, "org", event.OwnerLogin)
		assert.Equal(t, "repo", event.RepoName)
		assert.Equal(t, int64(100), event.RepoID)
		assert.Equal(t, int64(200), event.OwnerID)
		assert.Equal(t, int64(300), event.UserID)
		assert.Equal(t, "user-login", event.UserLogin)
		assert.Equal(t, "failure", event.Conclusion)
		assert.Equal(t, ts, event.Timestamp)
		// AgentID is not set during conversion — it's resolved by the handler
		// via appProvider.FindByID. Verify it defaults to zero.
		assert.Zero(t, event.AgentID)
	})

	t.Run("fails on invalid proto bytes", func(t *testing.T) {
		_, _, err := getAutomationRunRequestedEvent(context.Background(), []byte("not valid proto"), time.Now(), nil)
		require.Error(t, err)
		assert.Contains(t, err.Error(), "failed to unmarshal AutomationRunRequested")
	})
}
