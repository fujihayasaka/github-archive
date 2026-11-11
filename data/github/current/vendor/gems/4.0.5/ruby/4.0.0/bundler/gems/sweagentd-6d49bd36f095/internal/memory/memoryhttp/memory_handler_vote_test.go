package memoryhttp

import (
	"context"
	"net/http"
	"strings"
	"testing"

	"github.com/github/sweagentd/internal/memory/core"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/stretchr/testify/assert"
)

const handlerTestFact = "ExtensionLoader manages extension lifecycle"

func TestVoteMemorySuccess(t *testing.T) {
	voteCalled := false
	mockService := &MockMemoryService{
		VoteOnMemoryFunc: func(user core.User, repository *core.Repository, fact string, vote *core.Vote) error {
			voteCalled = true
			assert.Equal(t, handlerTestFact, fact)
			assert.Equal(t, core.UpVote, vote.Direction)
			assert.Equal(t, "copilot-swe-agent", vote.Source.Agent)
			assert.Equal(t, "abc123", vote.Source.CommitSHA)
			assert.Equal(t, core.RepoNWO{Owner: "test", Repo: "repo"}, vote.Source.RepoNWO)
			assert.Equal(t, uint64(1), vote.Source.UserID)
			assert.Equal(t, "testuser", vote.Source.UserLogin)
			assert.Equal(t, "verified in code", vote.Source.Reason)
			return nil
		},
	}

	_, router := createTestHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	body := `{"fact": "` + handlerTestFact + `", "direction": "upvote", "agent": "copilot-swe-agent", "commitSha": "abc123", "reason": "verified in code"}`
	req := createTestRequest(ctx, "POST", "/memory/v0/test/repo/vote", body)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusNoContent, rr.Code)
	assert.Empty(t, rr.Body.String())
	assert.True(t, voteCalled, "expected VoteOnMemory to be called")
}

func TestVoteMemoryDownvote(t *testing.T) {
	mockService := &MockMemoryService{
		VoteOnMemoryFunc: func(user core.User, repository *core.Repository, fact string, vote *core.Vote) error {
			assert.Equal(t, core.DownVote, vote.Direction)
			return nil
		},
	}

	_, router := createTestHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	body := `{"fact": "` + handlerTestFact + `", "direction": "downvote", "agent": "copilot-swe-agent", "reason": "outdated info"}`
	req := createTestRequest(ctx, "POST", "/memory/v0/test/repo/vote", body)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusNoContent, rr.Code)
}

func TestVoteMemoryInvalidDirection(t *testing.T) {
	mockService := &MockMemoryService{}

	_, router := createTestHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	body := `{"fact": "` + handlerTestFact + `", "direction": "invalid", "agent": "copilot-swe-agent"}`
	req := createTestRequest(ctx, "POST", "/memory/v0/test/repo/vote", body)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusBadRequest, rr.Code)
	assert.Contains(t, rr.Body.String(), `direction must be "upvote" or "downvote"`)
}

func TestVoteMemoryZeroDirection(t *testing.T) {
	mockService := &MockMemoryService{}

	_, router := createTestHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	body := `{"fact": "` + handlerTestFact + `", "direction": "", "agent": "copilot-swe-agent"}`
	req := createTestRequest(ctx, "POST", "/memory/v0/test/repo/vote", body)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusBadRequest, rr.Code)
	assert.Contains(t, rr.Body.String(), `direction must be "upvote" or "downvote"`)
}

func TestVoteMemoryEmptyFact(t *testing.T) {
	mockService := &MockMemoryService{}

	_, router := createTestHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	body := `{"fact": "", "direction": "upvote", "agent": "copilot-swe-agent"}`
	req := createTestRequest(ctx, "POST", "/memory/v0/test/repo/vote", body)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusBadRequest, rr.Code)
	assert.Contains(t, rr.Body.String(), "fact cannot be empty")
}

func TestVoteMemoryMissingFact(t *testing.T) {
	mockService := &MockMemoryService{}

	_, router := createTestHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	body := `{"direction": "upvote", "agent": "copilot-swe-agent"}`
	req := createTestRequest(ctx, "POST", "/memory/v0/test/repo/vote", body)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusBadRequest, rr.Code)
	assert.Contains(t, rr.Body.String(), "fact cannot be empty")
}

func TestVoteMemoryWhitespaceOnlyFact(t *testing.T) {
	mockService := &MockMemoryService{}

	_, router := createTestHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	body := `{"fact": "   ", "direction": "upvote", "agent": "copilot-swe-agent"}`
	req := createTestRequest(ctx, "POST", "/memory/v0/test/repo/vote", body)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusBadRequest, rr.Code)
	assert.Contains(t, rr.Body.String(), "fact cannot be empty")
}

func TestVoteMemoryInvalidBody(t *testing.T) {
	mockService := &MockMemoryService{}

	_, router := createTestHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	body := `not json`
	req := createTestRequest(ctx, "POST", "/memory/v0/test/repo/vote", body)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusBadRequest, rr.Code)
	assert.Contains(t, rr.Body.String(), "invalid request body")
}

func TestVoteMemoryNotFound(t *testing.T) {
	mockService := &MockMemoryService{
		VoteOnMemoryFunc: func(user core.User, repository *core.Repository, fact string, vote *core.Vote) error {
			return core.ErrMemoryFactNotFound
		},
	}

	_, router := createTestHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	body := `{"fact": "nonexistent fact", "direction": "upvote", "agent": "copilot-swe-agent", "reason": "verified in code"}`
	req := createTestRequest(ctx, "POST", "/memory/v0/test/repo/vote", body)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusUnprocessableEntity, rr.Code)
	assert.Contains(t, rr.Body.String(), "A memory with the specified fact and scope was not found.")
}

func TestVoteMemoryUnauthorized(t *testing.T) {
	mockService := &MockMemoryService{}

	_, router := createTestHandlerAndRouter(t, mockService)

	ctx := requestctx.AddData(context.Background(), &requestctx.CtxData{
		UserInfo: &requestctx.UserInfo{
			ID:         1,
			Login:      "testuser-none",
			TrackingID: "tracking-id",
		},
	})
	body := `{"fact": "` + handlerTestFact + `", "direction": "upvote", "agent": "copilot-swe-agent"}`
	req := createTestRequest(ctx, "POST", "/memory/v0/test/repo/vote", body)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusNotFound, rr.Code)
	assert.Contains(t, rr.Body.String(), "Could not verify access")
}

func TestVoteMemoryWithSessionID(t *testing.T) {
	mockService := &MockMemoryService{
		VoteOnMemoryFunc: func(user core.User, repository *core.Repository, fact string, vote *core.Vote) error {
			return nil
		},
	}

	_, router := createTestHandlerAndRouter(t, mockService)

	ctx := requestctx.AddData(context.Background(), &requestctx.CtxData{
		UserInfo: &requestctx.UserInfo{
			ID:         1,
			Login:      "testuser",
			TrackingID: "tracking-id",
			TokenInfo: &requestctx.TokenInfo{
				SessionID: 12345,
			},
		},
	})
	body := `{"fact": "` + handlerTestFact + `", "direction": "upvote", "agent": "copilot-swe-agent", "reason": "verified in code"}`
	req := createTestRequest(ctx, "POST", "/memory/v0/test/repo/vote", body)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusNoContent, rr.Code)
}

func TestVoteMemoryAgentTooLong(t *testing.T) {
	mockService := &MockMemoryService{}
	_, router := createTestHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	longAgent := strings.Repeat("a", maxVoteAgentLength+1)
	body := `{"fact": "` + handlerTestFact + `", "direction": "upvote", "agent": "` + longAgent + `", "reason": "test reason"}`
	req := createTestRequest(ctx, "POST", "/memory/v0/test/repo/vote", body)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusBadRequest, rr.Code)
	assert.Contains(t, rr.Body.String(), "agent must be at most")
}

func TestVoteMemoryCommitSHATooLong(t *testing.T) {
	mockService := &MockMemoryService{}
	_, router := createTestHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	longSHA := strings.Repeat("f", maxVoteCommitSHALength+1)
	body := `{"fact": "` + handlerTestFact + `", "direction": "upvote", "agent": "test", "commitSha": "` + longSHA + `", "reason": "test reason"}`
	req := createTestRequest(ctx, "POST", "/memory/v0/test/repo/vote", body)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusBadRequest, rr.Code)
	assert.Contains(t, rr.Body.String(), "commitSha must be at most")
}

func TestVoteMemoryConcurrencyConflict(t *testing.T) {
	mockService := &MockMemoryService{
		VoteOnMemoryFunc: func(user core.User, repository *core.Repository, fact string, vote *core.Vote) error {
			return core.ErrConcurrencyConflict
		},
	}

	_, router := createTestHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	body := `{"fact": "` + handlerTestFact + `", "direction": "upvote", "agent": "copilot-swe-agent", "reason": "verified in code"}`
	req := createTestRequest(ctx, "POST", "/memory/v0/test/repo/vote", body)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusConflict, rr.Code)
}

func TestVoteMemoryEmptyReason(t *testing.T) {
	mockService := &MockMemoryService{}

	_, router := createTestHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	body := `{"fact": "` + handlerTestFact + `", "direction": "upvote", "agent": "copilot-swe-agent", "reason": ""}`
	req := createTestRequest(ctx, "POST", "/memory/v0/test/repo/vote", body)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusBadRequest, rr.Code)
	assert.Contains(t, rr.Body.String(), "reason cannot be empty")
}

func TestVoteMemoryMissingReason(t *testing.T) {
	mockService := &MockMemoryService{}

	_, router := createTestHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	body := `{"fact": "` + handlerTestFact + `", "direction": "upvote", "agent": "copilot-swe-agent"}`
	req := createTestRequest(ctx, "POST", "/memory/v0/test/repo/vote", body)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusBadRequest, rr.Code)
	assert.Contains(t, rr.Body.String(), "reason cannot be empty")
}

func TestVoteMemoryWhitespaceOnlyReason(t *testing.T) {
	mockService := &MockMemoryService{}

	_, router := createTestHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	body := `{"fact": "` + handlerTestFact + `", "direction": "upvote", "agent": "copilot-swe-agent", "reason": "   "}`
	req := createTestRequest(ctx, "POST", "/memory/v0/test/repo/vote", body)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusBadRequest, rr.Code)
	assert.Contains(t, rr.Body.String(), "reason cannot be empty")
}

func TestVoteMemoryReasonTooLong(t *testing.T) {
	mockService := &MockMemoryService{}
	_, router := createTestHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	longReason := strings.Repeat("r", maxVoteReasonLength+1)
	body := `{"fact": "` + handlerTestFact + `", "direction": "upvote", "agent": "test", "reason": "` + longReason + `"}`
	req := createTestRequest(ctx, "POST", "/memory/v0/test/repo/vote", body)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusBadRequest, rr.Code)
	assert.Contains(t, rr.Body.String(), "reason must be at most")
}
