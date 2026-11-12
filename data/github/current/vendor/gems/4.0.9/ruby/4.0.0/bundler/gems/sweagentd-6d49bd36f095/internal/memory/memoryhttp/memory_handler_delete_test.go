package memoryhttp

import (
	"context"
	"net/http"
	"testing"
	"time"

	"github.com/github/hydro-client-go/v7/pkg/hydro"
	hydroSchemasv0 "github.com/github/hydro-schemas-go/hydro/schemas/sweagentd/v0"
	"github.com/github/sweagentd/internal/memory/core"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/encoding/protojson"
)

// TestDeleteMemorySuccess tests successful deletion of a memory.
func TestDeleteMemorySuccess(t *testing.T) {
	mockService := &MockMemoryService{
		DeleteMemoryFunc: func(user core.User, repository *core.Repository, memoryID core.MemoryID) error {
			assert.Equal(t, "test-memory-id", memoryID.String())
			return nil
		},
	}

	_, router := createTestHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	req := createTestRequest(ctx, "DELETE", "/memory/v0/test/repo/test-memory-id", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusNoContent, rr.Code)
	assert.Empty(t, rr.Body.String())
}

// TestDeleteMemoryNotFound tests deletion of a non-existent memory.
func TestDeleteMemoryNotFound(t *testing.T) {
	mockService := &MockMemoryService{
		DeleteMemoryFunc: func(user core.User, repository *core.Repository, memoryID core.MemoryID) error {
			return core.ErrMemoryNotFound
		},
	}

	_, router := createTestHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	req := createTestRequest(ctx, "DELETE", "/memory/v0/test/repo/non-existent-id", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusNotFound, rr.Code)
	assert.Contains(t, rr.Body.String(), "Memory not found")
}

// TestDeleteMemoryNoAccess tests deletion when user has no permissions at all.
// Users with no access should get 404 to avoid leaking repository existence.
func TestDeleteMemoryNoAccess(t *testing.T) {
	mockService := &MockMemoryService{}

	_, router := createTestHandlerAndRouter(t, mockService)

	ctx := requestctx.AddData(context.Background(), &requestctx.CtxData{
		UserInfo: &requestctx.UserInfo{
			ID:         1,
			Login:      "testuser-none", // This suffix gives no permissions
			TrackingID: "tracking-id",
		},
	})
	req := createTestRequest(ctx, "DELETE", "/memory/v0/test/repo/test-memory-id", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusNotFound, rr.Code)
	assert.Contains(t, rr.Body.String(), "Could not verify access to this repository")
}

// TestDeleteMemoryInsufficientPermissions tests deletion when user has read but not write access.
func TestDeleteMemoryInsufficientPermissions(t *testing.T) {
	mockService := &MockMemoryService{}

	_, router := createTestHandlerAndRouter(t, mockService)

	ctx := requestctx.AddData(context.Background(), &requestctx.CtxData{
		UserInfo: &requestctx.UserInfo{
			ID:         1,
			Login:      "testuser-read", // read-only permissions
			TrackingID: "tracking-id",
		},
	})
	req := createTestRequest(ctx, "DELETE", "/memory/v0/test/repo/test-memory-id", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusForbidden, rr.Code)
	assert.Contains(t, rr.Body.String(), "You don't have write access to this repository")
}

// TestDeleteMemoryEmptyID tests deletion with empty memory ID.
func TestDeleteMemoryEmptyID(t *testing.T) {
	mockService := &MockMemoryService{}
	_, router := createTestHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	req := createTestRequest(ctx, "DELETE", "/memory/v0/test/repo/", "")
	rr := executeRequestAndRecord(router, req)

	// This should route to HandleDeleteAllMemories instead
	assert.Equal(t, http.StatusNoContent, rr.Code)
}

// TestDeleteAllMemoriesSuccess tests successful deletion of all memories.
func TestDeleteAllMemoriesSuccess(t *testing.T) {
	mockService := &MockMemoryService{
		DeleteAllMemoriesFunc: func(user core.User, repository *core.Repository) error {
			assert.Equal(t, "test", repository.NWO.Owner)
			assert.Equal(t, "repo", repository.NWO.Repo)
			return nil
		},
	}

	_, router := createTestHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	req := createTestRequest(ctx, "DELETE", "/memory/v0/test/repo/", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusNoContent, rr.Code)
	assert.Empty(t, rr.Body.String())
}

// TestDeleteAllMemoriesNoAccess tests deletion of all memories when user has no permissions.
// Users with no access should get 404 to avoid leaking repository existence.
func TestDeleteAllMemoriesNoAccess(t *testing.T) {
	mockService := &MockMemoryService{}

	_, router := createTestHandlerAndRouter(t, mockService)

	ctx := requestctx.AddData(context.Background(), &requestctx.CtxData{
		UserInfo: &requestctx.UserInfo{
			ID:         1,
			Login:      "testuser-none", // This suffix gives no permissions
			TrackingID: "tracking-id",
		},
	})
	req := createTestRequest(ctx, "DELETE", "/memory/v0/test/repo/", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusNotFound, rr.Code)
	assert.Contains(t, rr.Body.String(), "Could not verify access to this repository")
}

// TestDeleteAllMemoriesInsufficientPermissions tests deletion of all memories when user has
// read but not write access.
func TestDeleteAllMemoriesInsufficientPermissions(t *testing.T) {
	mockService := &MockMemoryService{}

	_, router := createTestHandlerAndRouter(t, mockService)

	ctx := requestctx.AddData(context.Background(), &requestctx.CtxData{
		UserInfo: &requestctx.UserInfo{
			ID:         1,
			Login:      "testuser-read", // read-only permissions
			TrackingID: "tracking-id",
		},
	})
	req := createTestRequest(ctx, "DELETE", "/memory/v0/test/repo/", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusForbidden, rr.Code)
	assert.Contains(t, rr.Body.String(), "You don't have write access to this repository")
}

// TestDeleteAllMemoriesFeatureNotEnabled tests deletion when feature is disabled.
func TestDeleteAllMemoriesFeatureNotEnabled(t *testing.T) {
	mockService := &MockMemoryService{
		DeleteAllMemoriesFunc: func(user core.User, repository *core.Repository) error {
			return core.ErrFeatureNotEnabled
		},
	}

	_, router := createTestHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	req := createTestRequest(ctx, "DELETE", "/memory/v0/test/repo/", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusNotFound, rr.Code)
	assert.Contains(t, rr.Body.String(), "Resource not found")
}

// TestDeleteMemoryPublishesHydroEvent tests that a hydro telemetry event is published on successful single deletion.
func TestDeleteMemoryPublishesHydroEvent(t *testing.T) {
	mockService := &MockMemoryService{
		DeleteMemoryFunc: func(user core.User, repository *core.Repository, memoryID core.MemoryID) error {
			return nil
		},
	}

	messageChan := make(chan hydro.Message, 1)
	sink, err := hydro.NewMemorySink(messageChan)
	require.NoError(t, err)
	publisher, _ := hydro.NewPublisher(sink, hydro.WithEncoder(hydro.NewJSONEncoder()))
	noopObsv := observability.NewNoopExporters()
	obsv := noopObsv.WithPublisher(publisher)

	_, router := createTestHandlerAndRouterWithObsv(t, mockService, obsv, nil)

	ctx := createTestContext()
	req := createTestRequest(ctx, "DELETE", "/memory/v0/test/repo/test-memory-id", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusNoContent, rr.Code)

	select {
	case msg := <-messageChan:
		var event hydroSchemasv0.Telemetry
		err := protojson.Unmarshal(msg.Value, &event)
		require.NoError(t, err)
		assert.Equal(t, "memory_deleted", event.Kind)
		assert.Equal(t, "delete_single", event.Properties["operation"])
		assert.Equal(t, "test", event.Properties["repo_owner"])
		assert.Equal(t, "repo", event.Properties["repo_name"])
		assert.Equal(t, "test-memory-id", event.Properties["memory_id"])
		assert.Equal(t, "1", event.Properties["actor_id"])
		assert.Equal(t, "testuser", event.Properties["actor_login"])
	case <-time.After(1 * time.Second):
		t.Fatal("timeout waiting for hydro event on single delete")
	}
}

// TestDeleteAllMemoriesPublishesHydroEvent tests that a hydro telemetry event is published on successful bulk deletion.
func TestDeleteAllMemoriesPublishesHydroEvent(t *testing.T) {
	mockService := &MockMemoryService{
		DeleteAllMemoriesFunc: func(user core.User, repository *core.Repository) error {
			return nil
		},
	}

	messageChan := make(chan hydro.Message, 1)
	sink, err := hydro.NewMemorySink(messageChan)
	require.NoError(t, err)
	publisher, _ := hydro.NewPublisher(sink, hydro.WithEncoder(hydro.NewJSONEncoder()))
	noopObsv := observability.NewNoopExporters()
	obsv := noopObsv.WithPublisher(publisher)

	_, router := createTestHandlerAndRouterWithObsv(t, mockService, obsv, nil)

	ctx := createTestContext()
	req := createTestRequest(ctx, "DELETE", "/memory/v0/test/repo/", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusNoContent, rr.Code)

	select {
	case msg := <-messageChan:
		var event hydroSchemasv0.Telemetry
		err := protojson.Unmarshal(msg.Value, &event)
		require.NoError(t, err)
		assert.Equal(t, "memory_deleted", event.Kind)
		assert.Equal(t, "delete_all", event.Properties["operation"])
		assert.Equal(t, "test", event.Properties["repo_owner"])
		assert.Equal(t, "repo", event.Properties["repo_name"])
		assert.Empty(t, event.Properties["memory_id"])
		assert.Equal(t, "1", event.Properties["actor_id"])
		assert.Equal(t, "testuser", event.Properties["actor_login"])
	case <-time.After(1 * time.Second):
		t.Fatal("timeout waiting for hydro event on delete all")
	}
}
