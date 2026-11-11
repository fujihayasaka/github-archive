package memory

import (
	"context"
	"errors"
	"testing"

	"github.com/github/sweagentd/internal/customagent/store"
	"github.com/google/uuid"
)

func newTestRecord(scopeID int64, path string) *store.AgentRecord {
	return &store.AgentRecord{
		ID:      uuid.NewString(),
		ScopeID: scopeID,
		Path:    path,
		Config: store.AgentConfig{
			Name:        "test-agent",
			DisplayName: "Test Agent",
			Description: "A test agent",
			Prompt:      "You are a test agent.",
			Tools:       []string{"bash"},
		},
		TreeOID: "abc123",
	}
}

func TestUpsert(t *testing.T) {
	s := NewStore()
	ctx := context.Background()

	record := newTestRecord(100, ".github/agents/test.md")
	result, err := s.Upsert(ctx, record)
	if err != nil {
		t.Fatalf("Upsert failed: %v", err)
	}
	if result.ID != record.ID {
		t.Errorf("expected ID %s, got %s", record.ID, result.ID)
	}
	if result.ETag == nil {
		t.Error("expected ETag to be set")
	}
	if result.CreatedAt == 0 {
		t.Error("expected CreatedAt to be set")
	}
	if result.SyncedAt == 0 {
		t.Error("expected SyncedAt to be set")
	}
}

func TestUpsertNil(t *testing.T) {
	s := NewStore()
	ctx := context.Background()

	_, err := s.Upsert(ctx, nil)
	if err == nil {
		t.Fatal("expected error for nil record")
	}
}

func TestUpsertOverwrite(t *testing.T) {
	s := NewStore()
	ctx := context.Background()

	record := newTestRecord(100, ".github/agents/test.md")
	_, err := s.Upsert(ctx, record)
	if err != nil {
		t.Fatalf("first Upsert failed: %v", err)
	}

	record.Config.Description = "Updated description"
	result, err := s.Upsert(ctx, record)
	if err != nil {
		t.Fatalf("second Upsert failed: %v", err)
	}
	if result.Config.Description != "Updated description" {
		t.Errorf("expected updated description, got %s", result.Config.Description)
	}
}

func TestGet(t *testing.T) {
	s := NewStore()
	ctx := context.Background()

	record := newTestRecord(100, ".github/agents/test.md")
	_, err := s.Upsert(ctx, record)
	if err != nil {
		t.Fatalf("Upsert failed: %v", err)
	}

	got, err := s.Get(ctx, 100, record.ID)
	if err != nil {
		t.Fatalf("Get failed: %v", err)
	}
	if got.ID != record.ID {
		t.Errorf("expected ID %s, got %s", record.ID, got.ID)
	}
	if got.Config.Name != "test-agent" {
		t.Errorf("expected name test-agent, got %s", got.Config.Name)
	}
}

func TestGetNotFound(t *testing.T) {
	s := NewStore()
	ctx := context.Background()

	_, err := s.Get(ctx, 100, "nonexistent")
	if !errors.Is(err, store.ErrAgentNotFound) {
		t.Errorf("expected ErrAgentNotFound, got %v", err)
	}
}

func TestGetByPath(t *testing.T) {
	s := NewStore()
	ctx := context.Background()

	record := newTestRecord(100, ".github/agents/review.md")
	_, err := s.Upsert(ctx, record)
	if err != nil {
		t.Fatalf("Upsert failed: %v", err)
	}

	got, err := s.GetByPath(ctx, 100, ".github/agents/review.md")
	if err != nil {
		t.Fatalf("GetByPath failed: %v", err)
	}
	if got.ID != record.ID {
		t.Errorf("expected ID %s, got %s", record.ID, got.ID)
	}
}

func TestGetByPathNotFound(t *testing.T) {
	s := NewStore()
	ctx := context.Background()

	_, err := s.GetByPath(ctx, 100, ".github/agents/nonexistent.md")
	if !errors.Is(err, store.ErrAgentNotFound) {
		t.Errorf("expected ErrAgentNotFound, got %v", err)
	}
}

func TestList(t *testing.T) {
	s := NewStore()
	ctx := context.Background()

	r1 := newTestRecord(100, ".github/agents/a.md")
	r2 := newTestRecord(100, ".github/agents/b.md")
	r3 := newTestRecord(200, ".github/agents/c.md")

	for _, r := range []*store.AgentRecord{r1, r2, r3} {
		_, err := s.Upsert(ctx, r)
		if err != nil {
			t.Fatalf("Upsert failed: %v", err)
		}
	}

	records, err := s.List(ctx, 100)
	if err != nil {
		t.Fatalf("List failed: %v", err)
	}
	if len(records) != 2 {
		t.Errorf("expected 2 records for scopeID 100, got %d", len(records))
	}

	records, err = s.List(ctx, 200)
	if err != nil {
		t.Fatalf("List failed: %v", err)
	}
	if len(records) != 1 {
		t.Errorf("expected 1 record for scopeID 200, got %d", len(records))
	}
}

func TestListEmpty(t *testing.T) {
	s := NewStore()
	ctx := context.Background()

	records, err := s.List(ctx, 999)
	if err != nil {
		t.Fatalf("List failed: %v", err)
	}
	if len(records) != 0 {
		t.Errorf("expected 0 records, got %d", len(records))
	}
}

func TestDelete(t *testing.T) {
	s := NewStore()
	ctx := context.Background()

	record := newTestRecord(100, ".github/agents/test.md")
	_, err := s.Upsert(ctx, record)
	if err != nil {
		t.Fatalf("Upsert failed: %v", err)
	}

	err = s.Delete(ctx, 100, record.ID)
	if err != nil {
		t.Fatalf("Delete failed: %v", err)
	}

	_, err = s.Get(ctx, 100, record.ID)
	if !errors.Is(err, store.ErrAgentNotFound) {
		t.Errorf("expected ErrAgentNotFound after delete, got %v", err)
	}
}

func TestDeleteNotFound(t *testing.T) {
	s := NewStore()
	ctx := context.Background()

	err := s.Delete(ctx, 100, "nonexistent")
	if !errors.Is(err, store.ErrAgentNotFound) {
		t.Errorf("expected ErrAgentNotFound, got %v", err)
	}
}

func TestDeleteByScopeID(t *testing.T) {
	s := NewStore()
	ctx := context.Background()

	r1 := newTestRecord(100, ".github/agents/a.md")
	r2 := newTestRecord(100, ".github/agents/b.md")
	r3 := newTestRecord(200, ".github/agents/c.md")

	for _, r := range []*store.AgentRecord{r1, r2, r3} {
		_, err := s.Upsert(ctx, r)
		if err != nil {
			t.Fatalf("Upsert failed: %v", err)
		}
	}

	err := s.DeleteByScopeID(ctx, 100)
	if err != nil {
		t.Fatalf("DeleteByScopeID failed: %v", err)
	}

	records, err := s.List(ctx, 100)
	if err != nil {
		t.Fatalf("List failed: %v", err)
	}
	if len(records) != 0 {
		t.Errorf("expected 0 records for scopeID 100, got %d", len(records))
	}

	// Scope 200 should be unaffected
	records, err = s.List(ctx, 200)
	if err != nil {
		t.Fatalf("List failed: %v", err)
	}
	if len(records) != 1 {
		t.Errorf("expected 1 record for scopeID 200, got %d", len(records))
	}
}

func TestDeleteByScopeIDEmpty(t *testing.T) {
	s := NewStore()
	ctx := context.Background()

	// Deleting a nonexistent scope should not error
	err := s.DeleteByScopeID(ctx, 999)
	if err != nil {
		t.Fatalf("DeleteByScopeID on empty scope should not fail: %v", err)
	}
}

func TestReturnedRecordsAreIsolated(t *testing.T) {
	s := NewStore()
	ctx := context.Background()

	record := newTestRecord(100, ".github/agents/test.md")
	_, err := s.Upsert(ctx, record)
	if err != nil {
		t.Fatalf("Upsert failed: %v", err)
	}

	got1, _ := s.Get(ctx, 100, record.ID)
	got2, _ := s.Get(ctx, 100, record.ID)

	got1.Config.Description = "modified"
	if got2.Config.Description == "modified" {
		t.Error("mutations on returned record should not affect stored record")
	}
}

func TestReturnedSlicesAreIsolated(t *testing.T) {
	s := NewStore()
	ctx := context.Background()

	record := newTestRecord(100, ".github/agents/test.md")
	_, err := s.Upsert(ctx, record)
	if err != nil {
		t.Fatalf("Upsert failed: %v", err)
	}

	got, _ := s.Get(ctx, 100, record.ID)
	got.Config.Tools[0] = "mutated"

	got2, _ := s.Get(ctx, 100, record.ID)
	if got2.Config.Tools[0] == "mutated" {
		t.Error("mutations on returned slice should not affect stored record")
	}
}

func TestUpsertSetsUpdatedAt(t *testing.T) {
	s := NewStore()
	ctx := context.Background()

	record := newTestRecord(100, ".github/agents/test.md")
	result, err := s.Upsert(ctx, record)
	if err != nil {
		t.Fatalf("Upsert failed: %v", err)
	}
	if result.UpdatedAt == 0 {
		t.Error("expected UpdatedAt to be set on Upsert")
	}
}
