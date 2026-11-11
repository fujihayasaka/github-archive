package memoryhttp

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/github/hydro-client-go/v7/pkg/hydro"
	hydroSchemasv0 "github.com/github/hydro-schemas-go/hydro/schemas/sweagentd/v0"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/memory/core"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/encoding/protojson"
)

// TestDeleteMemoriesSuccess tests successful batch deletion returns 200 with deleted IDs.
func TestDeleteMemoriesSuccess(t *testing.T) {
	memoryIDs := []core.MemoryID{"mem-1", "mem-2", "mem-3"}

	mockService := &MockMemoryService{
		DeleteMemoriesFunc: func(user core.User, repository *core.Repository, ids []core.MemoryID) (*core.BatchDeleteResult, error) {
			assert.Equal(t, memoryIDs, ids)
			assert.Equal(t, "test", repository.NWO.Owner)
			assert.Equal(t, "repo", repository.NWO.Repo)
			return &core.BatchDeleteResult{Deleted: ids}, nil
		},
	}

	_, router := createTestHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	body := `{"ids": ["mem-1", "mem-2", "mem-3"]}`
	req := createTestRequest(ctx, "POST", "/memory/v0/test/repo/delete", body)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)

	var resp BatchDeleteResponse
	err := json.NewDecoder(rr.Body).Decode(&resp)
	require.NoError(t, err)
	assert.Equal(t, []string{"mem-1", "mem-2", "mem-3"}, resp.Deleted)
	assert.Empty(t, resp.Failed)
}

// TestDeleteMemoriesSingleID tests batch deletion with a single ID.
func TestDeleteMemoriesSingleID(t *testing.T) {
	mockService := &MockMemoryService{
		DeleteMemoriesFunc: func(user core.User, repository *core.Repository, ids []core.MemoryID) (*core.BatchDeleteResult, error) {
			assert.Len(t, ids, 1)
			assert.Equal(t, core.MemoryID("mem-1"), ids[0])
			return &core.BatchDeleteResult{Deleted: ids}, nil
		},
	}

	_, router := createTestHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	body := `{"ids": ["mem-1"]}`
	req := createTestRequest(ctx, "POST", "/memory/v0/test/repo/delete", body)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)

	var resp BatchDeleteResponse
	err := json.NewDecoder(rr.Body).Decode(&resp)
	require.NoError(t, err)
	assert.Equal(t, []string{"mem-1"}, resp.Deleted)
	assert.Empty(t, resp.Failed)
}

// TestDeleteMemoriesEmptyIDs tests that an empty IDs list returns 400.
func TestDeleteMemoriesEmptyIDs(t *testing.T) {
	mockService := &MockMemoryService{}
	_, router := createTestHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	body := `{"ids": []}`
	req := createTestRequest(ctx, "POST", "/memory/v0/test/repo/delete", body)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusBadRequest, rr.Code)
	assert.Contains(t, rr.Body.String(), "ids cannot be empty")
}

// TestDeleteMemoriesTooManyIDs tests that exceeding the max batch size returns 400.
func TestDeleteMemoriesTooManyIDs(t *testing.T) {
	mockService := &MockMemoryService{}
	_, router := createTestHandlerAndRouter(t, mockService)

	// Build a request with 501 IDs (exceeds maxBatchDeleteSize of 500)
	ids := make([]string, 501)
	for i := range ids {
		ids[i] = fmt.Sprintf(`"mem-%d"`, i)
	}
	body := fmt.Sprintf(`{"ids": [%s]}`, strings.Join(ids, ","))

	ctx := createTestContext()
	req := createTestRequest(ctx, "POST", "/memory/v0/test/repo/delete", body)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusBadRequest, rr.Code)
	assert.Contains(t, rr.Body.String(), "too many ids, maximum is 500")
}

// TestDeleteMemoriesInvalidBody tests that a malformed JSON body returns 400.
func TestDeleteMemoriesInvalidBody(t *testing.T) {
	mockService := &MockMemoryService{}
	_, router := createTestHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	body := `not valid json`
	req := createTestRequest(ctx, "POST", "/memory/v0/test/repo/delete", body)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusBadRequest, rr.Code)
	assert.Contains(t, rr.Body.String(), "invalid request body")
}

// TestDeleteMemoriesMissingIDsField tests that a body without the ids field returns 400.
func TestDeleteMemoriesMissingIDsField(t *testing.T) {
	mockService := &MockMemoryService{}
	_, router := createTestHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	body := `{"something": "else"}`
	req := createTestRequest(ctx, "POST", "/memory/v0/test/repo/delete", body)
	rr := executeRequestAndRecord(router, req)

	// IDs will unmarshal as nil/empty → "ids cannot be empty"
	assert.Equal(t, http.StatusBadRequest, rr.Code)
	assert.Contains(t, rr.Body.String(), "ids cannot be empty")
}

// TestDeleteMemoriesFeatureNotEnabled tests that a service ErrFeatureNotEnabled returns 404.
func TestDeleteMemoriesFeatureNotEnabled(t *testing.T) {
	mockService := &MockMemoryService{
		DeleteMemoriesFunc: func(user core.User, repository *core.Repository, ids []core.MemoryID) (*core.BatchDeleteResult, error) {
			return nil, core.ErrFeatureNotEnabled
		},
	}

	_, router := createTestHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	body := `{"ids": ["mem-1"]}`
	req := createTestRequest(ctx, "POST", "/memory/v0/test/repo/delete", body)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusNotFound, rr.Code)
	assert.Contains(t, rr.Body.String(), "Resource not found")
}

// TestDeleteMemoriesPartialFailure tests that a partial failure returns 200 with both
// deleted and failed IDs when some items were successfully deleted before the error.
func TestDeleteMemoriesPartialFailure(t *testing.T) {
	mockService := &MockMemoryService{
		DeleteMemoriesFunc: func(user core.User, repository *core.Repository, ids []core.MemoryID) (*core.BatchDeleteResult, error) {
			return &core.BatchDeleteResult{
				Deleted: []core.MemoryID{"mem-1", "mem-2"},
				Failed:  []core.MemoryID{"mem-3", "mem-4"},
			}, errors.New("transactional batch delete returned unsuccessful status")
		},
	}

	_, router := createTestHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	body := `{"ids": ["mem-1", "mem-2", "mem-3", "mem-4"]}`
	req := createTestRequest(ctx, "POST", "/memory/v0/test/repo/delete", body)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)

	var resp BatchDeleteResponse
	err := json.NewDecoder(rr.Body).Decode(&resp)
	require.NoError(t, err)
	assert.Equal(t, []string{"mem-1", "mem-2"}, resp.Deleted)
	assert.Equal(t, []string{"mem-3", "mem-4"}, resp.Failed)
}

// TestDeleteMemoriesTotalFailure tests that a total failure (no items deleted) returns
// an error response, not a 200 with empty deleted.
func TestDeleteMemoriesTotalFailure(t *testing.T) {
	mockService := &MockMemoryService{
		DeleteMemoriesFunc: func(user core.User, repository *core.Repository, ids []core.MemoryID) (*core.BatchDeleteResult, error) {
			return &core.BatchDeleteResult{
				Failed: []core.MemoryID{"mem-1", "mem-2"},
			}, errors.New("transactional batch delete failed completely")
		},
	}

	_, router := createTestHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	body := `{"ids": ["mem-1", "mem-2"]}`
	req := createTestRequest(ctx, "POST", "/memory/v0/test/repo/delete", body)
	rr := executeRequestAndRecord(router, req)

	// Total failure should not return 200
	assert.NotEqual(t, http.StatusOK, rr.Code)
}

// TestDeleteMemoriesNilResultError tests that a nil result with an error (e.g. auth failure)
// returns the domain error, not a 200.
func TestDeleteMemoriesNilResultError(t *testing.T) {
	mockService := &MockMemoryService{
		DeleteMemoriesFunc: func(user core.User, repository *core.Repository, ids []core.MemoryID) (*core.BatchDeleteResult, error) {
			return nil, core.ErrRepositoryNotFound
		},
	}

	_, router := createTestHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	body := `{"ids": ["mem-1"]}`
	req := createTestRequest(ctx, "POST", "/memory/v0/test/repo/delete", body)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusNotFound, rr.Code)
}

// TestDeleteMemoriesUnauthorized tests that a user with read-only permissions gets 403.
func TestDeleteMemoriesUnauthorized(t *testing.T) {
	mockService := &MockMemoryService{}

	_, router := createTestHandlerAndRouter(t, mockService)

	ctx := requestctx.AddData(context.Background(), &requestctx.CtxData{
		UserInfo: &requestctx.UserInfo{
			ID:         1,
			Login:      "testuser-read", // read-only permissions
			TrackingID: "tracking-id",
		},
	})
	body := `{"ids": ["mem-1"]}`
	req := createTestRequest(ctx, "POST", "/memory/v0/test/repo/delete", body)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusForbidden, rr.Code)
	assert.Contains(t, rr.Body.String(), "You don't have write access to this repository")
}

// TestDeleteMemoriesNoAccess tests that a user with no permissions gets 404 to avoid
// leaking repository existence.
func TestDeleteMemoriesNoAccess(t *testing.T) {
	mockService := &MockMemoryService{}

	_, router := createTestHandlerAndRouter(t, mockService)

	ctx := requestctx.AddData(context.Background(), &requestctx.CtxData{
		UserInfo: &requestctx.UserInfo{
			ID:         1,
			Login:      "testuser-none", // no permissions at all
			TrackingID: "tracking-id",
		},
	})
	body := `{"ids": ["mem-1"]}`
	req := createTestRequest(ctx, "POST", "/memory/v0/test/repo/delete", body)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusNotFound, rr.Code)
	assert.Contains(t, rr.Body.String(), "Could not verify access to this repository")
}

// TestDeleteMemoriesPublishesHydroEvent tests that a hydro telemetry event is published on success.
func TestDeleteMemoriesPublishesHydroEvent(t *testing.T) {
	mockService := &MockMemoryService{
		DeleteMemoriesFunc: func(user core.User, repository *core.Repository, ids []core.MemoryID) (*core.BatchDeleteResult, error) {
			return &core.BatchDeleteResult{Deleted: ids}, nil
		},
	}

	messageChan := make(chan hydro.Message, 1)
	sink, err := hydro.NewMemorySink(messageChan)
	require.NoError(t, err)
	publisher, _ := hydro.NewPublisher(sink, hydro.WithEncoder(hydro.NewJSONEncoder()))
	noopObsv := observability.NewNoopExporters()
	obsv := noopObsv.WithPublisher(publisher)

	ffClient := featureflags.NewNoopClient(map[string]bool{})

	_, router := createTestHandlerAndRouterWithObsv(t, mockService, obsv, ffClient)

	ctx := createTestContext()
	body := `{"ids": ["mem-1", "mem-2"]}`
	req := createTestRequest(ctx, "POST", "/memory/v0/test/repo/delete", body)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)

	select {
	case msg := <-messageChan:
		var event hydroSchemasv0.Telemetry
		err := protojson.Unmarshal(msg.Value, &event)
		require.NoError(t, err)
		assert.Equal(t, "memory_deleted", event.Kind)
		assert.Equal(t, "delete_batch", event.Properties["operation"])
		assert.Equal(t, "1", event.Properties["actor_id"])
	case <-time.After(1 * time.Second):
		t.Fatal("timeout waiting for hydro event on batch delete")
	}
}

// TestDeleteMemoriesResponseContentType verifies the response has JSON content type.
func TestDeleteMemoriesResponseContentType(t *testing.T) {
	mockService := &MockMemoryService{
		DeleteMemoriesFunc: func(user core.User, repository *core.Repository, ids []core.MemoryID) (*core.BatchDeleteResult, error) {
			return &core.BatchDeleteResult{Deleted: ids}, nil
		},
	}

	_, router := createTestHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	body := `{"ids": ["mem-1"]}`
	req := createTestRequest(ctx, "POST", "/memory/v0/test/repo/delete", body)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)
	assert.Contains(t, rr.Header().Get("Content-Type"), "application/json")
}
