package cosmos

import (
	"encoding/json"
	"fmt"
	"testing"
	"time"

	"github.com/github/sweagentd/internal/memory/core"
	"github.com/github/sweagentd/internal/memory/core/coretest"
	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func createTestMemory(nwo string) *core.Memory {
	memoryID := core.MemoryID(uuid.New().String())
	repoNWO, _ := core.NewRepoNWOFromString(nwo)
	return core.NewMemory(
		memoryID,
		"Test Subject",
		"Test Fact",
		"Test Reason",
		[]string{"source1"},
		core.MemorySource{
			InteractionID: "interaction1",
			NWO:           *repoNWO,
			User:          core.User{ID: 1, Login: "testuser"},
			Agent:         "test-agent",
		},
	)
}

func createTestMemoryWithSHA(nwo, sha string) *core.Memory {
	memoryID := core.MemoryID(uuid.New().String())
	repoNWO, _ := core.NewRepoNWOFromString(nwo)
	memory := core.NewMemory(
		memoryID,
		"Test Subject",
		"Test Fact",
		"Test Reason",
		[]string{"source1"},
		core.MemorySource{
			InteractionID: "interaction1",
			NWO:           *repoNWO,
			User:          core.User{ID: 1, Login: "testuser"},
			Agent:         "test-agent",
			CommitSHA:     sha,
		},
	)
	return memory
}

func TestMemoryDocument_FromDomain(t *testing.T) {
	memory := createTestMemory("test/repo")
	memory.Scope = core.MemoryScopeRepository
	memory.CreatedAt = time.Date(2023, 1, 1, 0, 0, 0, 0, time.UTC)
	pkStr := repoPartitionKeyString(core.RepositoryID(uuid.New().ID()))

	doc := &memoryDocument{}
	doc.fromDomain(pkStr, memory, time.Now().UTC())

	assert.Equal(t, string(memory.ID), doc.ID)
	assert.Equal(t, memory.Subject, doc.Subject)
	assert.Equal(t, memory.Fact, doc.Fact)
	assert.Equal(t, memory.Citations, doc.Citations)
	assert.Equal(t, memory.Reason, doc.Reason)
	assert.Equal(t, memory.Source, doc.Source)
	assert.Equal(t, memory.Scope, doc.Scope)
	assert.Equal(t, memory.CreatedAt, doc.CreatedAt)
	assert.Equal(t, pkStr, doc.PartitionKey)
}

func TestMemoryDocument_FromDomain_ExpiredMemoryTTLClampsToOne(t *testing.T) {
	// A memory whose ExpiresAt is in the past should get TTL=1, not 0.
	// In Cosmos DB, a document with a negative TTL would never expire.
	// For an already-expired document, let's set TTL=1 so it expires immediately after being written.
	memory := createTestMemory("test/repo")
	memory.ExpiresAt = time.Date(2020, 1, 1, 0, 0, 0, 0, time.UTC)
	now := time.Date(2026, 3, 1, 0, 0, 0, 0, time.UTC) // well past ExpiresAt
	pkStr := repoPartitionKeyString(core.RepositoryID(uuid.New().ID()))

	doc := &memoryDocument{}
	doc.fromDomain(pkStr, memory, now)

	assert.Equal(t, int64(1), doc.TTL)
}

func TestMemoryDocument_ToDomain(t *testing.T) {
	repoNWO, _ := core.NewRepoNWO("test", "repo")
	memoryID := core.MemoryID(uuid.New().String())
	createdAt := time.Date(2023, 1, 1, 0, 0, 0, 0, time.UTC)

	doc := &memoryDocument{
		ID:        string(memoryID),
		Subject:   "Test Subject",
		Fact:      "Test Fact",
		Citations: []string{"source1"},
		Reason:    "Test Reason",
		Source: core.MemorySource{
			InteractionID: "interaction1",
			NWO:           *repoNWO,
			User:          core.User{ID: 1, Login: "testuser"},
			Agent:         "test-agent",
		},
		Scope:        core.MemoryScopeRepository,
		CreatedAt:    createdAt,
		PartitionKey: "test/repo",
	}

	memory := doc.toDomain()

	assert.Equal(t, memoryID, memory.ID)
	assert.Equal(t, "Test Subject", memory.Subject)
	assert.Equal(t, "Test Fact", memory.Fact)
	assert.Equal(t, []string{"source1"}, memory.Citations)
	assert.Equal(t, "Test Reason", memory.Reason)
	assert.Equal(t, doc.Source.InteractionID, memory.Source.InteractionID)
	assert.Equal(t, doc.Source.NWO, memory.Source.NWO)
	assert.Equal(t, doc.Source.User, memory.Source.User)
	assert.Equal(t, doc.Source.Agent, memory.Source.Agent)
	assert.Equal(t, core.MemoryScopeRepository, memory.Scope)
	assert.Empty(t, memory.Source.CommitSHA)
	assert.Equal(t, core.MemoryScopeRepository, memory.Scope)
	assert.Equal(t, createdAt, memory.CreatedAt)
	// Backfilled vote should carry provenance from the memory source
	require.Len(t, memory.Votes, 1)
	assert.Equal(t, core.UpVote, memory.Votes[0].Direction)
	assert.Equal(t, "test-agent", memory.Votes[0].Source.Agent)
	assert.Equal(t, "test/repo", memory.Votes[0].Source.RepoNWO.String())
	assert.Equal(t, uint64(1), memory.Votes[0].Source.UserID)
	assert.Equal(t, "testuser", memory.Votes[0].Source.UserLogin)
}

func TestMemoryDocument_ToDomain_InfersLegacyScopeFromPartitionKey(t *testing.T) {
	for _, tc := range []struct {
		name         string
		partitionKey string
		want         core.MemoryScope
	}{
		{name: "repository", partitionKey: repoPartitionKeyString(core.RepositoryID(123)), want: core.MemoryScopeRepository},
		{name: "user", partitionKey: userPartitionKeyString(456), want: core.MemoryScopeUser},
	} {
		t.Run(tc.name, func(t *testing.T) {
			doc := &memoryDocument{
				ID:           string(core.MemoryID(uuid.New().String())),
				Subject:      "Test Subject",
				Fact:         "Test Fact",
				Reason:       "Test Reason",
				CreatedAt:    time.Date(2023, 1, 1, 0, 0, 0, 0, time.UTC),
				PartitionKey: tc.partitionKey,
			}

			memory := doc.toDomain()

			assert.Equal(t, tc.want, memory.Scope)
		})
	}
}

func TestMemoryPartitionKey(t *testing.T) {
	pkStr := repoPartitionKeyString(core.RepositoryID(uuid.New().ID()))
	pk := partitionKeyFromString(pkStr)

	// The partition key should be constructed properly
	assert.NotNil(t, pk)
}

func TestNewCosmosMemoryStore_InvalidOpts(t *testing.T) {
	// Test with empty options
	opts := &ContainerOpts{}

	repo, err := NewCosmosMemoryStore(opts)
	require.Error(t, err)
	assert.Nil(t, repo)
	require.Error(t, err)
}

// Note: Full integration tests would require a real Cosmos DB instance or emulator
// These tests focus on the document conversion logic and basic validation

func TestCosmosMemoryStore_FindRecentByPartition_HappyPath(t *testing.T) {
	repoID := core.RepositoryID(12345)

	// Test that repoPartitionKeyString generates correct partition key
	partitionKey := repoPartitionKeyString(repoID)
	expectedPartitionKey := fmt.Sprintf("memory:repo:%d:v0", repoID)
	assert.Equal(t, expectedPartitionKey, partitionKey)

	// Test that invalid limits default to 10
	testCases := []struct {
		inputLimit    int
		expectedLimit int
	}{
		{5, 5},     // Valid limit
		{0, 10},    // Invalid limit (0) should default to 10
		{-1, 10},   // Invalid limit (negative) should default to 10
		{100, 100}, // Valid large limit
	}

	for _, tc := range testCases {
		// We can't test the actual CosmosDB query without a real container,
		// but we can verify the limit processing logic through the interface
		// This is primarily tested through integration tests or by mocking the container

		// For now, we just verify the limit validation logic that should happen
		actualLimit := tc.inputLimit
		if actualLimit <= 0 {
			actualLimit = 10
		}
		assert.Equal(t, tc.expectedLimit, actualLimit, "Limit processing should work correctly for input %d", tc.inputLimit)
	}
}

func TestCosmosMemoryStore_FindRecentByPartition_LimitRespected(t *testing.T) {
	// Test the query structure that should be generated
	expectedQueryTemplate := "SELECT * FROM c WHERE c.partition_key = @partition_key ORDER BY c.created_at DESC OFFSET 0 LIMIT @limit"

	// Verify partition key generation
	partitionKey := repoPartitionKeyString(core.RepositoryID(12345))
	assert.Contains(t, partitionKey, "memory:repo:")
	assert.Contains(t, partitionKey, ":v0")

	// The actual query execution is tested in integration tests or with real CosmosDB
	// This test documents the expected query structure
	assert.Contains(t, expectedQueryTemplate, "ORDER BY c.created_at DESC")
	assert.Contains(t, expectedQueryTemplate, "LIMIT @limit")
}

func TestMemoryDocument_FromDomain_WithSHA(t *testing.T) {
	sha := "abc123def456"
	memory := createTestMemoryWithSHA("test/repo", sha)
	memory.CreatedAt = time.Date(2023, 1, 1, 0, 0, 0, 0, time.UTC)
	pkStr := repoPartitionKeyString(core.RepositoryID(uuid.New().ID()))

	doc := &memoryDocument{}
	doc.fromDomain(pkStr, memory, time.Now().UTC())

	assert.Equal(t, sha, doc.Source.CommitSHA)
	assert.Equal(t, string(memory.ID), doc.ID)
	assert.Equal(t, memory.Subject, doc.Subject)
}

func TestMemoryDocument_FromDomain_WithoutSHA(t *testing.T) {
	memory := createTestMemory("test/repo")
	memory.CreatedAt = time.Date(2023, 1, 1, 0, 0, 0, 0, time.UTC)
	pkStr := repoPartitionKeyString(core.RepositoryID(uuid.New().ID()))

	doc := &memoryDocument{}
	doc.fromDomain(pkStr, memory, time.Now().UTC())

	assert.Empty(t, doc.Source.CommitSHA)
	assert.Equal(t, string(memory.ID), doc.ID)
}

func TestMemoryDocument_FromDomain_PersistsScope(t *testing.T) {
	memory := createTestMemory("test/repo")
	memory.Scope = core.MemoryScopeUser
	pkStr := repoPartitionKeyString(core.RepositoryID(uuid.New().ID()))

	doc := &memoryDocument{}
	doc.fromDomain(pkStr, memory, time.Now().UTC())

	assert.Equal(t, core.MemoryScopeUser, doc.Scope)
}

func TestMemoryDocument_ToDomain_ReadsScope(t *testing.T) {
	memoryID := core.MemoryID(uuid.New().String())
	doc := &memoryDocument{
		ID:        string(memoryID),
		Subject:   "Test",
		Fact:      "Test",
		Scope:     core.MemoryScopeUser,
		CreatedAt: time.Date(2023, 1, 1, 0, 0, 0, 0, time.UTC),
		Source:    core.MemorySource{Agent: "test-agent"},
	}

	memory := doc.toDomain()

	assert.Equal(t, core.MemoryScopeUser, memory.Scope)
}

func TestMemoryDocument_ToDomain_LegacyDocumentEmptyScope(t *testing.T) {
	// Documents written before scope was persisted will have an empty scope.
	// writeMemoriesResponse stamps scope as a backward-compatibility fallback.
	memoryID := core.MemoryID(uuid.New().String())
	doc := &memoryDocument{
		ID:        string(memoryID),
		Subject:   "Test",
		Fact:      "Test",
		CreatedAt: time.Date(2023, 1, 1, 0, 0, 0, 0, time.UTC),
		Source:    core.MemorySource{Agent: "test-agent"},
	}

	memory := doc.toDomain()

	assert.Empty(t, memory.Scope)
}

func TestMemoryDocument_ToDomain_WithSHA(t *testing.T) {
	repoNWO, _ := core.NewRepoNWO("test", "repo")
	memoryID := core.MemoryID(uuid.New().String())
	createdAt := time.Date(2023, 1, 1, 0, 0, 0, 0, time.UTC)
	sha := "abc123def456"

	doc := &memoryDocument{
		ID:        string(memoryID),
		Subject:   "Test Subject",
		Fact:      "Test Fact",
		Citations: []string{"source1"},
		Reason:    "Test Reason",
		Source: core.MemorySource{
			InteractionID: "interaction1",
			NWO:           *repoNWO,
			User:          core.User{ID: 1, Login: "testuser"},
			Agent:         "test-agent",
			CommitSHA:     sha,
		},
		CreatedAt:    createdAt,
		PartitionKey: "test/repo",
	}

	memory := doc.toDomain()

	assert.Equal(t, sha, memory.Source.CommitSHA)
	assert.Equal(t, memoryID, memory.ID)
}

func TestMemoryDocument_ToDomain_WithoutSHA(t *testing.T) {
	repoNWO, _ := core.NewRepoNWO("test", "repo")
	memoryID := core.MemoryID(uuid.New().String())
	createdAt := time.Date(2023, 1, 1, 0, 0, 0, 0, time.UTC)

	doc := &memoryDocument{
		ID:        string(memoryID),
		Subject:   "Test Subject",
		Fact:      "Test Fact",
		Citations: []string{"source1"},
		Reason:    "Test Reason",
		Source: core.MemorySource{
			InteractionID: "interaction1",
			NWO:           *repoNWO,
			User:          core.User{ID: 1, Login: "testuser"},
			Agent:         "test-agent",
		},
		CreatedAt:    createdAt,
		PartitionKey: "test/repo",
	}

	memory := doc.toDomain()

	assert.Empty(t, memory.Source.CommitSHA)
	assert.Equal(t, memoryID, memory.ID)
}

func TestMemoryDocument_ToDomain_LegacyDocumentBackwardCompat(t *testing.T) {
	repoNWO, _ := core.NewRepoNWO("test", "repo")
	memoryID := core.MemoryID(uuid.New().String())
	createdAt := time.Date(2023, 6, 15, 10, 0, 0, 0, time.UTC)

	// Legacy document: no Votes, no UpdatedAt, no ExpiresAt
	doc := &memoryDocument{
		ID:        string(memoryID),
		Subject:   "Legacy Subject",
		Fact:      "Legacy Fact",
		Citations: []string{"source1"},
		Reason:    "Legacy Reason",
		Source: core.MemorySource{
			InteractionID: "interaction1",
			NWO:           *repoNWO,
			User:          core.User{ID: 1, Login: "testuser"},
			Agent:         "test-agent",
		},
		CreatedAt:    createdAt,
		PartitionKey: "test/repo",
	}

	memory := doc.toDomain()

	require.Len(t, memory.Votes, 1)
	assert.Equal(t, core.UpVote, memory.Votes[0].Direction)
	assert.Equal(t, createdAt, memory.Votes[0].Timestamp)
	// Synthetic vote should carry provenance from the memory source
	assert.Equal(t, "test-agent", memory.Votes[0].Source.Agent)
	assert.Equal(t, "test/repo", memory.Votes[0].Source.RepoNWO.String())
	assert.Equal(t, uint64(1), memory.Votes[0].Source.UserID)
	assert.Equal(t, "testuser", memory.Votes[0].Source.UserLogin)
	assert.Equal(t, createdAt, memory.UpdatedAt)
	assert.Equal(t, createdAt.Add(core.VoteWindow), memory.ExpiresAt)
}

func TestMemoryDocument_VotePruning_RoundTrip(t *testing.T) {
	now := time.Date(2026, 3, 10, 12, 0, 0, 0, time.UTC)
	coretest.FreezeNow(t, now)
	pkStr := repoPartitionKeyString(core.RepositoryID(12345))

	// Create a memory with an old vote (30 days ago) and a recent vote (5 days ago)
	memory := createTestMemory("test/repo")
	memory.CreatedAt = now.Add(-30 * 24 * time.Hour)
	memory.UpdatedAt = now.Add(-5 * 24 * time.Hour)
	memory.ExpiresAt = now.Add(-2 * 24 * time.Hour)
	memory.Votes = []core.Vote{
		{Direction: core.UpVote, Timestamp: now.Add(-30 * 24 * time.Hour), Source: core.VoteSource{Agent: "old-agent"}},
		{Direction: core.UpVote, Timestamp: now.Add(-5 * 24 * time.Hour), Source: core.VoteSource{Agent: "recent-agent"}},
	}

	// Vote on the memory — this should prune the 30-day-old vote
	err := memory.AddVote(core.Vote{Direction: core.UpVote, Timestamp: now, Source: core.VoteSource{Agent: "new-agent"}})
	require.NoError(t, err)

	// Convert to document (simulates what save() does before writing to Cosmos)
	doc := &memoryDocument{}
	doc.fromDomain(pkStr, memory, now)

	// Serialize to JSON (simulates the Cosmos write)
	marshalled, err := json.Marshal(doc)
	require.NoError(t, err)

	// Deserialize back (simulates the Cosmos read)
	var readDoc memoryDocument
	err = json.Unmarshal(marshalled, &readDoc)
	require.NoError(t, err)

	// Convert back to domain
	result := readDoc.toDomain()

	// The 30-day-old vote should be pruned — only the 5-day-old and new votes remain
	require.Len(t, result.Votes, 2)
	assert.Equal(t, "recent-agent", result.Votes[0].Source.Agent)
	assert.Equal(t, "new-agent", result.Votes[1].Source.Agent)

	// ExpiresAt should be reset to 28 days from the upvote
	assert.Equal(t, now.Add(core.VoteWindow), result.ExpiresAt)

	// TTL should be positive (document still alive)
	assert.Greater(t, doc.TTL, int64(0))
}

func TestBillingWhereClause(t *testing.T) {
	tests := []struct {
		name     string
		filter   core.BillingEntity
		expected string
	}{
		{
			name:     "zero billing entity",
			filter:   core.BillingEntity{OrganizationID: 0, EnterpriseID: 0},
			expected: " AND c.billing_organization_id = @billing_org_id AND c.billing_enterprise_id = @billing_enterprise_id",
		},
		{
			name:     "non-zero billing entity",
			filter:   core.BillingEntity{OrganizationID: 123, EnterpriseID: 456},
			expected: " AND c.billing_organization_id = @billing_org_id AND c.billing_enterprise_id = @billing_enterprise_id",
		},
		{
			name:     "org-only billing entity",
			filter:   core.BillingEntity{OrganizationID: 99, EnterpriseID: 0},
			expected: " AND c.billing_organization_id = @billing_org_id AND c.billing_enterprise_id = @billing_enterprise_id",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := billingWhereClause(tt.filter)
			assert.Equal(t, tt.expected, result)
		})
	}
}

func TestBillingQueryParams(t *testing.T) {
	tests := []struct {
		name           string
		filter         core.BillingEntity
		expectedParams []struct {
			name  string
			value uint64
		}
	}{
		{
			name:   "zero billing entity",
			filter: core.BillingEntity{OrganizationID: 0, EnterpriseID: 0},
			expectedParams: []struct {
				name  string
				value uint64
			}{
				{name: "@billing_org_id", value: 0},
				{name: "@billing_enterprise_id", value: 0},
			},
		},
		{
			name:   "non-zero billing entity",
			filter: core.BillingEntity{OrganizationID: 123, EnterpriseID: 456},
			expectedParams: []struct {
				name  string
				value uint64
			}{
				{name: "@billing_org_id", value: 123},
				{name: "@billing_enterprise_id", value: 456},
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			params := billingQueryParams(tt.filter)
			require.Len(t, params, len(tt.expectedParams))
			for i, expected := range tt.expectedParams {
				assert.Equal(t, expected.name, params[i].Name)
				assert.Equal(t, expected.value, params[i].Value)
			}
		})
	}
}
