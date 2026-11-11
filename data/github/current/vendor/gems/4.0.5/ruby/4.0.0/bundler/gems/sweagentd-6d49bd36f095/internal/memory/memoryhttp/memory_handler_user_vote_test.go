package memoryhttp

import (
	"net/http"
	"strings"
	"testing"

	"github.com/github/sweagentd/internal/memory/core"
	"github.com/stretchr/testify/assert"
)

const userVoteTestFact = "User prefers tabs over spaces"

func TestVoteUserMemorySuccess(t *testing.T) {
	voteCalled := false
	mockService := &MockMemoryService{
		VoteOnUserMemoryFunc: func(user core.User, fact string, vote *core.Vote) error {
			voteCalled = true
			assert.Equal(t, userVoteTestFact, fact)
			assert.Equal(t, core.UpVote, vote.Direction)
			assert.Equal(t, "copilot-swe-agent", vote.Source.Agent)
			assert.Equal(t, "abc123", vote.Source.CommitSHA)
			assert.Equal(t, uint64(1), vote.Source.UserID)
			assert.Equal(t, "testuser", vote.Source.UserLogin)
			// User-scoped vote should NOT have a RepoNWO set
			assert.Equal(t, core.RepoNWO{}, vote.Source.RepoNWO)
			return nil
		},
	}

	_, router := createTestUserHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	body := `{"fact": "` + userVoteTestFact + `", "direction": "upvote", "agent": "copilot-swe-agent", "commitSha": "abc123", "reason": "user confirmed preference"}`
	req := createTestRequest(ctx, "POST", "/memory/v0/user/vote", body)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusNoContent, rr.Code)
	assert.Empty(t, rr.Body.String())
	assert.True(t, voteCalled, "expected VoteOnUserMemory to be called")
}

func TestVoteUserMemoryDownvote(t *testing.T) {
	mockService := &MockMemoryService{
		VoteOnUserMemoryFunc: func(user core.User, fact string, vote *core.Vote) error {
			assert.Equal(t, core.DownVote, vote.Direction)
			return nil
		},
	}

	_, router := createTestUserHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	body := `{"fact": "` + userVoteTestFact + `", "direction": "downvote", "agent": "copilot-swe-agent", "reason": "user rejected preference"}`
	req := createTestRequest(ctx, "POST", "/memory/v0/user/vote", body)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusNoContent, rr.Code)
}

func TestVoteUserMemoryInvalidDirection(t *testing.T) {
	mockService := &MockMemoryService{}

	_, router := createTestUserHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	body := `{"fact": "` + userVoteTestFact + `", "direction": "invalid", "agent": "copilot-swe-agent", "reason": "test reason"}`
	req := createTestRequest(ctx, "POST", "/memory/v0/user/vote", body)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusBadRequest, rr.Code)
	assert.Contains(t, rr.Body.String(), `direction must be "upvote" or "downvote"`)
}

func TestVoteUserMemoryEmptyFact(t *testing.T) {
	mockService := &MockMemoryService{}

	_, router := createTestUserHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	body := `{"fact": "", "direction": "upvote", "agent": "copilot-swe-agent", "reason": "test reason"}`
	req := createTestRequest(ctx, "POST", "/memory/v0/user/vote", body)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusBadRequest, rr.Code)
	assert.Contains(t, rr.Body.String(), "fact cannot be empty")
}

func TestVoteUserMemoryInvalidBody(t *testing.T) {
	mockService := &MockMemoryService{}

	_, router := createTestUserHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	body := `not json`
	req := createTestRequest(ctx, "POST", "/memory/v0/user/vote", body)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusBadRequest, rr.Code)
	assert.Contains(t, rr.Body.String(), "invalid request body")
}

func TestVoteUserMemoryNotFound(t *testing.T) {
	mockService := &MockMemoryService{
		VoteOnUserMemoryFunc: func(user core.User, fact string, vote *core.Vote) error {
			return core.ErrMemoryFactNotFound
		},
	}

	_, router := createTestUserHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	body := `{"fact": "nonexistent fact", "direction": "upvote", "agent": "copilot-swe-agent", "reason": "test reason"}`
	req := createTestRequest(ctx, "POST", "/memory/v0/user/vote", body)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusUnprocessableEntity, rr.Code)
	assert.Contains(t, rr.Body.String(), "A memory with the specified fact and scope was not found.")
}

func TestVoteUserMemoryConcurrencyConflict(t *testing.T) {
	mockService := &MockMemoryService{
		VoteOnUserMemoryFunc: func(user core.User, fact string, vote *core.Vote) error {
			return core.ErrConcurrencyConflict
		},
	}

	_, router := createTestUserHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	body := `{"fact": "` + userVoteTestFact + `", "direction": "upvote", "agent": "copilot-swe-agent", "reason": "test reason"}`
	req := createTestRequest(ctx, "POST", "/memory/v0/user/vote", body)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusConflict, rr.Code)
}

func TestVoteUserMemoryAgentTooLong(t *testing.T) {
	mockService := &MockMemoryService{}
	_, router := createTestUserHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	longAgent := strings.Repeat("a", maxVoteAgentLength+1)
	body := `{"fact": "` + userVoteTestFact + `", "direction": "upvote", "agent": "` + longAgent + `", "reason": "test reason"}`
	req := createTestRequest(ctx, "POST", "/memory/v0/user/vote", body)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusBadRequest, rr.Code)
	assert.Contains(t, rr.Body.String(), "agent must be at most")
}
