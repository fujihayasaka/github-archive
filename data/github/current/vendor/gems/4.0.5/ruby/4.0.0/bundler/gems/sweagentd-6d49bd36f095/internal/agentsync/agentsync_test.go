package agentsync

import (
	"context"
	"errors"
	"testing"

	"github.com/github/hydro-schemas-go/hydro/schemas/github/v1/entities"
	sweagentdv1 "github.com/github/hydro-schemas-go/hydro/schemas/sweagentd/v1"
	sweagentdv1entities "github.com/github/hydro-schemas-go/hydro/schemas/sweagentd/v1/entities"
	"github.com/github/sweagentd/internal/agentconfig"
	"github.com/github/sweagentd/internal/customagent/store"
	"github.com/github/sweagentd/internal/customagent/store/memory"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/sweagentd"
	"github.com/google/uuid"
	"google.golang.org/protobuf/types/known/wrapperspb"
)

func TestNewSyncEvent_RepositoryScope(t *testing.T) {
	msg := &sweagentdv1.AgentsUpdated{
		Repository: &entities.Repository{
			Id:      42,
			Name:    "my-repo",
			OwnerId: wrapperspb.UInt32(100),
		},
		RepositoryOwner: &entities.User{
			Id:    100,
			Login: "my-org",
		},
		Actor: &entities.User{
			Id:    200,
			Login: "pusher",
		},
		CommitSha: "abc123",
		ChangedFiles: []*sweagentdv1entities.ChangedFile{
			{
				ChangeType:  sweagentdv1entities.ChangeType_ADDITION,
				CurrentPath: ".github/agents/my-agent.md",
			},
		},
	}

	event, err := NewSyncEvent(msg)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if event.Scope != agentconfig.ScopeRepository {
		t.Errorf("expected scope %q, got %q", agentconfig.ScopeRepository, event.Scope)
	}
	if event.ScopeID != 42 {
		t.Errorf("expected scopeID 42, got %d", event.ScopeID)
	}
	if event.RepoID != 42 {
		t.Errorf("expected repoID 42, got %d", event.RepoID)
	}
	if event.Directory != RepoAgentsDir {
		t.Errorf("expected directory %q, got %q", RepoAgentsDir, event.Directory)
	}
	if event.ActorID != 200 {
		t.Errorf("expected actorID 200, got %d", event.ActorID)
	}
	if len(event.ChangedFiles) != 1 {
		t.Errorf("expected 1 changed file, got %d", len(event.ChangedFiles))
	}
	if event.ChangedFiles[0].ChangeType != ChangeTypeAddition {
		t.Errorf("expected change type %d, got %d", ChangeTypeAddition, event.ChangedFiles[0].ChangeType)
	}
}

func TestNewSyncEvent_OrganizationScope(t *testing.T) {
	for _, repoName := range []string{".github", ".github-private"} {
		t.Run(repoName, func(t *testing.T) {
			msg := &sweagentdv1.AgentsUpdated{
				Repository: &entities.Repository{
					Id:      99,
					Name:    repoName,
					OwnerId: wrapperspb.UInt32(500),
				},
				RepositoryOwner: &entities.User{
					Id:    500,
					Login: "my-org",
				},
				Actor: &entities.User{
					Id:    200,
					Login: "pusher",
				},
				CommitSha: "def456",
			}

			event, err := NewSyncEvent(msg)
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}

			if event.Scope != agentconfig.ScopeOrganization {
				t.Errorf("expected scope %q, got %q", agentconfig.ScopeOrganization, event.Scope)
			}
			if event.ScopeID != 500 {
				t.Errorf("expected scopeID 500 (owner ID), got %d", event.ScopeID)
			}
			if event.Directory != OrgAgentsDir {
				t.Errorf("expected directory %q, got %q", OrgAgentsDir, event.Directory)
			}
		})
	}
}

func TestNewSyncEvent_MissingRepository(t *testing.T) {
	msg := &sweagentdv1.AgentsUpdated{
		CommitSha: "abc123",
	}
	_, err := NewSyncEvent(msg)
	if err == nil {
		t.Fatal("expected error for missing repository")
	}
}

func TestNewSyncEvent_MissingCommitSHA(t *testing.T) {
	msg := &sweagentdv1.AgentsUpdated{
		Repository: &entities.Repository{
			Id:      42,
			Name:    "my-repo",
			OwnerId: wrapperspb.UInt32(100),
		},
	}
	_, err := NewSyncEvent(msg)
	if err == nil {
		t.Fatal("expected error for missing commit_sha")
	}
}

func TestNewSyncEvent_MissingActor(t *testing.T) {
	msg := &sweagentdv1.AgentsUpdated{
		Repository: &entities.Repository{
			Id:      42,
			Name:    "my-repo",
			OwnerId: wrapperspb.UInt32(100),
		},
		RepositoryOwner: &entities.User{
			Id:    100,
			Login: "my-org",
		},
		CommitSha: "abc123",
	}
	_, err := NewSyncEvent(msg)
	if err == nil {
		t.Fatal("expected error for missing actor")
	}
}

func TestNewSyncEvent_MissingActorLogin(t *testing.T) {
	msg := &sweagentdv1.AgentsUpdated{
		Repository: &entities.Repository{
			Id:      42,
			Name:    "my-repo",
			OwnerId: wrapperspb.UInt32(100),
		},
		RepositoryOwner: &entities.User{
			Id:    100,
			Login: "my-org",
		},
		Actor: &entities.User{
			Id: 200,
		},
		CommitSha: "abc123",
	}
	_, err := NewSyncEvent(msg)
	if err == nil {
		t.Fatal("expected error for missing actor login")
	}
}

func TestSyncEvent_HasOnlyModifications(t *testing.T) {
	tests := []struct {
		name     string
		files    []ChangedFile
		expected bool
	}{
		{
			name:     "empty",
			files:    nil,
			expected: false,
		},
		{
			name: "all modifications",
			files: []ChangedFile{
				{ChangeType: ChangeTypeModification},
				{ChangeType: ChangeTypeModification},
			},
			expected: true,
		},
		{
			name: "mixed changes",
			files: []ChangedFile{
				{ChangeType: ChangeTypeModification},
				{ChangeType: ChangeTypeAddition},
			},
			expected: false,
		},
		{
			name: "deletion",
			files: []ChangedFile{
				{ChangeType: ChangeTypeDeletion},
			},
			expected: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			event := &SyncEvent{ChangedFiles: tt.files}
			if got := event.HasOnlyModifications(); got != tt.expected {
				t.Errorf("HasOnlyModifications() = %v, want %v", got, tt.expected)
			}
		})
	}
}

func TestIsOrgAgentRepo(t *testing.T) {
	tests := []struct {
		name     string
		expected bool
	}{
		{".github", true},
		{".github-private", true},
		{"my-repo", false},
		{"github", false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := IsOrgAgentRepo(tt.name); got != tt.expected {
				t.Errorf("IsOrgAgentRepo(%q) = %v, want %v", tt.name, got, tt.expected)
			}
		})
	}
}

func TestDirectoryForScope(t *testing.T) {
	if got := DirectoryForScope(agentconfig.ScopeRepository); got != RepoAgentsDir {
		t.Errorf("expected %q, got %q", RepoAgentsDir, got)
	}
	if got := DirectoryForScope(agentconfig.ScopeOrganization); got != OrgAgentsDir {
		t.Errorf("expected %q, got %q", OrgAgentsDir, got)
	}
	if got := DirectoryForScope(agentconfig.ScopeEnterprise); got != OrgAgentsDir {
		t.Errorf("expected %q, got %q", OrgAgentsDir, got)
	}
}

func TestAgentNameFromPath(t *testing.T) {
	tests := []struct {
		dir      string
		path     string
		expected string
	}{
		{".github/agents", ".github/agents/my-agent.md", "my-agent"},
		{".github/agents", ".github/agents/my-agent.agent.md", "my-agent"},
		{"agents", "agents/triage.md", "triage"},
	}

	for _, tt := range tests {
		t.Run(tt.path, func(t *testing.T) {
			if got := agentNameFromPath(tt.dir, tt.path); got != tt.expected {
				t.Errorf("expected %q, got %q", tt.expected, got)
			}
		})
	}
}

func TestIsAgentFile(t *testing.T) {
	tests := []struct {
		path     string
		expected bool
	}{
		{".github/agents/my-agent.md", true},
		{".github/agents/my-agent.agent.md", true},
		{".github/agents/README.md", false},
		{".github/agents/config.yaml", false},
		{".github/agents/notes.txt", false},
	}

	for _, tt := range tests {
		t.Run(tt.path, func(t *testing.T) {
			if got := isAgentFile(tt.path); got != tt.expected {
				t.Errorf("isAgentFile(%q) = %v, want %v", tt.path, got, tt.expected)
			}
		})
	}
}

// mockFileReader is a test double for FileReader.
type mockFileReader struct {
	trees    []*sweagentd.SpokesObject
	treeOID  string
	treeErr  error
	blobs    [][]byte
	blobErr  error
	blobByID map[string][]byte
}

func (m *mockFileReader) ListTrees(_ context.Context, _ uint64, _ string) ([]*sweagentd.SpokesObject, string, error) {
	return m.trees, m.treeOID, m.treeErr
}

func (m *mockFileReader) ReadBlobObjects(_ context.Context, _ uint64, _ []string) ([][]byte, error) {
	return m.blobs, m.blobErr
}

func (m *mockFileReader) ReadBlobByObjectIDPath(_ context.Context, _ uint64, oid, path string) ([]byte, error) {
	key := oid + ":" + path
	if data, ok := m.blobByID[key]; ok {
		return data, nil
	}
	return nil, nil
}

func validAgentMarkdown(name string) string {
	return "---\ndescription: A test agent named " + name + "\n---\nDo stuff"
}

func TestReconciler_FullReconcile_AddNew(t *testing.T) {
	files := &mockFileReader{
		trees: []*sweagentd.SpokesObject{
			{Oid: "oid1", Path: ".github/agents/agent-a.md"},
		},
		blobs: [][]byte{
			[]byte(validAgentMarkdown("agent-a")),
		},
	}

	agentStore := memory.NewStore()
	obsv := observability.NewNoopExporters()
	reconciler := NewReconciler(files, obsv)

	event := &SyncEvent{
		Scope:     agentconfig.ScopeRepository,
		ScopeID:   42,
		RepoID:    42,
		CommitSHA: "abc123",
		Directory: RepoAgentsDir,
		ChangedFiles: []ChangedFile{
			{ChangeType: ChangeTypeAddition, CurrentPath: ".github/agents/agent-a.md"},
		},
	}

	parse := simpleParse
	result, err := reconciler.Reconcile(context.Background(), agentStore, event, parse)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if result.Added != 1 {
		t.Errorf("expected 1 added, got %d", result.Added)
	}
	if result.Updated != 0 {
		t.Errorf("expected 0 updated, got %d", result.Updated)
	}
	if result.Deleted != 0 {
		t.Errorf("expected 0 deleted, got %d", result.Deleted)
	}

	// Verify the record is in the store
	records, err := agentStore.List(context.Background(), 42)
	if err != nil {
		t.Fatalf("unexpected error listing records: %v", err)
	}
	if len(records) != 1 {
		t.Fatalf("expected 1 record, got %d", len(records))
	}
	if records[0].Path != ".github/agents/agent-a.md" {
		t.Errorf("expected path .github/agents/agent-a.md, got %s", records[0].Path)
	}
}

func TestReconciler_FullReconcile_NormalizesRelativePaths(t *testing.T) {
	// ListTrees may return paths relative to the listed directory (e.g., "agent-a.md"
	// instead of ".github/agents/agent-a.md"). Verify that the reconciler normalizes
	// these to repo-root-relative paths for consistency with the modifications-only path.
	files := &mockFileReader{
		trees: []*sweagentd.SpokesObject{
			{Oid: "oid1", Path: "agent-a.md"}, // relative path from ListTrees
		},
		blobs: [][]byte{
			[]byte(validAgentMarkdown("agent-a")),
		},
	}

	agentStore := memory.NewStore()
	obsv := observability.NewNoopExporters()
	reconciler := NewReconciler(files, obsv)

	event := &SyncEvent{
		Scope:     agentconfig.ScopeRepository,
		ScopeID:   42,
		RepoID:    42,
		CommitSHA: "abc123",
		Directory: RepoAgentsDir,
		ChangedFiles: []ChangedFile{
			{ChangeType: ChangeTypeAddition, CurrentPath: ".github/agents/agent-a.md"},
		},
	}

	result, err := reconciler.Reconcile(context.Background(), agentStore, event, simpleParse)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if result.Added != 1 {
		t.Errorf("expected 1 added, got %d", result.Added)
	}

	records, _ := agentStore.List(context.Background(), 42)
	if len(records) != 1 {
		t.Fatalf("expected 1 record, got %d", len(records))
	}
	// Path should be normalized to repo-root-relative form
	if records[0].Path != ".github/agents/agent-a.md" {
		t.Errorf("expected normalized path .github/agents/agent-a.md, got %s", records[0].Path)
	}
}

func TestReconciler_FullReconcile_DeleteOrphaned(t *testing.T) {
	files := &mockFileReader{
		trees: []*sweagentd.SpokesObject{},
		blobs: [][]byte{},
	}

	agentStore := memory.NewStore()
	obsv := observability.NewNoopExporters()

	// Pre-populate with a record that will become orphaned
	_, err := agentStore.Upsert(context.Background(), &store.AgentRecord{
		ID:      uuid.NewString(),
		ScopeID: 42,
		Path:    ".github/agents/old-agent.md",
		Config: store.AgentConfig{
			Name:        "old-agent",
			Description: "will be deleted",
		},
	})
	if err != nil {
		t.Fatalf("setup error: %v", err)
	}

	reconciler := NewReconciler(files, obsv)
	event := &SyncEvent{
		Scope:     agentconfig.ScopeRepository,
		ScopeID:   42,
		RepoID:    42,
		CommitSHA: "abc123",
		Directory: RepoAgentsDir,
		ChangedFiles: []ChangedFile{
			{ChangeType: ChangeTypeDeletion, CurrentPath: ".github/agents/old-agent.md"},
		},
	}

	result, err := reconciler.Reconcile(context.Background(), agentStore, event, simpleParse)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if result.Deleted != 1 {
		t.Errorf("expected 1 deleted, got %d", result.Deleted)
	}

	// Verify the store is empty
	records, _ := agentStore.List(context.Background(), 42)
	if len(records) != 0 {
		t.Errorf("expected 0 records, got %d", len(records))
	}
}

func TestReconciler_FullReconcile_UpdateExisting(t *testing.T) {
	files := &mockFileReader{
		trees: []*sweagentd.SpokesObject{
			{Oid: "oid1", Path: ".github/agents/agent-a.md"},
		},
		blobs: [][]byte{
			[]byte(validAgentMarkdown("agent-a")),
		},
	}

	agentStore := memory.NewStore()
	obsv := observability.NewNoopExporters()

	existingID := uuid.NewString()
	_, err := agentStore.Upsert(context.Background(), &store.AgentRecord{
		ID:      existingID,
		ScopeID: 42,
		Path:    ".github/agents/agent-a.md",
		Config: store.AgentConfig{
			Name:        "agent-a",
			Description: "old description",
		},
	})
	if err != nil {
		t.Fatalf("setup error: %v", err)
	}

	reconciler := NewReconciler(files, obsv)
	event := &SyncEvent{
		Scope:     agentconfig.ScopeRepository,
		ScopeID:   42,
		RepoID:    42,
		CommitSHA: "abc123",
		Directory: RepoAgentsDir,
		ChangedFiles: []ChangedFile{
			{ChangeType: ChangeTypeModification, CurrentPath: ".github/agents/agent-a.md"},
			{ChangeType: ChangeTypeAddition, CurrentPath: ".github/agents/other.yml"}, // non-modification, forces full reconcile
		},
	}

	result, err := reconciler.Reconcile(context.Background(), agentStore, event, simpleParse)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if result.Updated != 1 {
		t.Errorf("expected 1 updated, got %d", result.Updated)
	}

	// Verify the ID was preserved
	records, _ := agentStore.List(context.Background(), 42)
	if len(records) != 1 {
		t.Fatalf("expected 1 record, got %d", len(records))
	}
	if records[0].ID != existingID {
		t.Errorf("expected ID %q preserved, got %q", existingID, records[0].ID)
	}
}

func TestReconciler_ModificationsOnly(t *testing.T) {
	blobByID := map[string][]byte{
		"sha123:.github/agents/agent-a.md": []byte(validAgentMarkdown("agent-a")),
	}

	files := &mockFileReader{
		blobByID: blobByID,
	}

	agentStore := memory.NewStore()
	obsv := observability.NewNoopExporters()

	existingID := uuid.NewString()
	_, err := agentStore.Upsert(context.Background(), &store.AgentRecord{
		ID:      existingID,
		ScopeID: 42,
		Path:    ".github/agents/agent-a.md",
		Config:  store.AgentConfig{Name: "agent-a", Description: "old"},
	})
	if err != nil {
		t.Fatalf("setup error: %v", err)
	}

	reconciler := NewReconciler(files, obsv)
	event := &SyncEvent{
		Scope:     agentconfig.ScopeRepository,
		ScopeID:   42,
		RepoID:    42,
		CommitSHA: "sha123",
		Directory: RepoAgentsDir,
		ChangedFiles: []ChangedFile{
			{ChangeType: ChangeTypeModification, CurrentPath: ".github/agents/agent-a.md"},
		},
	}

	result, err := reconciler.Reconcile(context.Background(), agentStore, event, simpleParse)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if result.Updated != 1 {
		t.Errorf("expected 1 updated, got %d", result.Updated)
	}

	// Verify record was updated but ID preserved
	records, _ := agentStore.List(context.Background(), 42)
	if len(records) != 1 {
		t.Fatalf("expected 1 record, got %d", len(records))
	}
	if records[0].ID != existingID {
		t.Errorf("expected ID %q preserved, got %q", existingID, records[0].ID)
	}
}

func TestNoopEnterpriseResolver(t *testing.T) {
	resolver := &NoopEnterpriseResolver{}
	id, err := resolver.IsEnterpriseAgentRepo(context.Background(), 123)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if id != 0 {
		t.Errorf("expected 0, got %d", id)
	}
}

// simpleParse is a test parse function that creates a basic AgentConfig from any valid markdown.
func simpleParse(_ string, contents []byte, name string) (*store.AgentConfig, error) {
	return &store.AgentConfig{
		Name:        name,
		Description: "parsed: " + name,
	}, nil
}

// parseWithValidationError simulates a validation error that returns a partial config.
func parseWithValidationError(_ string, _ []byte, name string) (*store.AgentConfig, error) {
	return &store.AgentConfig{
		Name:        name,
		Description: "partial config",
	}, errors.New("invalid config: field \"target\" has bad value")
}

// parseWithHardError simulates a hard parse error with no partial config.
func parseWithHardError(_ string, _ []byte, _ string) (*store.AgentConfig, error) {
	return nil, errors.New("malformed markdown: missing frontmatter")
}

func TestReconciler_FullReconcile_ValidationError_UpsertsWithSyncError(t *testing.T) {
	files := &mockFileReader{
		trees: []*sweagentd.SpokesObject{
			{Oid: "oid1", Path: ".github/agents/bad-agent.md"},
		},
		blobs: [][]byte{
			[]byte("bad content"),
		},
	}

	agentStore := memory.NewStore()
	obsv := observability.NewNoopExporters()
	reconciler := NewReconciler(files, obsv)

	event := &SyncEvent{
		Scope:     agentconfig.ScopeRepository,
		ScopeID:   42,
		RepoID:    42,
		OwnerID:   100,
		CommitSHA: "abc123",
		Directory: RepoAgentsDir,
		ChangedFiles: []ChangedFile{
			{ChangeType: ChangeTypeAddition, CurrentPath: ".github/agents/bad-agent.md"},
		},
	}

	result, err := reconciler.Reconcile(context.Background(), agentStore, event, parseWithValidationError)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if result.Errors != 1 {
		t.Errorf("expected 1 error, got %d", result.Errors)
	}
	if result.Added != 0 {
		t.Errorf("expected 0 added, got %d", result.Added)
	}

	// Verify a record was upserted with SyncError and partial config
	records, err := agentStore.List(context.Background(), 42)
	if err != nil {
		t.Fatalf("unexpected error listing records: %v", err)
	}
	if len(records) != 1 {
		t.Fatalf("expected 1 record, got %d", len(records))
	}
	if records[0].SyncError == "" {
		t.Error("expected SyncError to be set")
	}
	if records[0].Config.Description != "partial config" {
		t.Errorf("expected partial config description, got %q", records[0].Config.Description)
	}
}

func TestReconciler_FullReconcile_HardError_PreservesExistingRecord(t *testing.T) {
	files := &mockFileReader{
		trees: []*sweagentd.SpokesObject{
			{Oid: "oid1", Path: ".github/agents/broken.md"},
		},
		blobs: [][]byte{
			[]byte("broken content"),
		},
	}

	agentStore := memory.NewStore()
	obsv := observability.NewNoopExporters()

	existingID := uuid.NewString()
	_, err := agentStore.Upsert(context.Background(), &store.AgentRecord{
		ID:      existingID,
		ScopeID: 42,
		Path:    ".github/agents/broken.md",
		Config:  store.AgentConfig{Name: "broken", Description: "previously valid"},
	})
	if err != nil {
		t.Fatalf("setup error: %v", err)
	}

	reconciler := NewReconciler(files, obsv)
	event := &SyncEvent{
		Scope:     agentconfig.ScopeRepository,
		ScopeID:   42,
		RepoID:    42,
		OwnerID:   100,
		CommitSHA: "def456",
		Directory: RepoAgentsDir,
		ChangedFiles: []ChangedFile{
			{ChangeType: ChangeTypeModification, CurrentPath: ".github/agents/broken.md"},
			{ChangeType: ChangeTypeAddition, CurrentPath: ".github/agents/other.yml"},
		},
	}

	result, err := reconciler.Reconcile(context.Background(), agentStore, event, parseWithHardError)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if result.Errors != 1 {
		t.Errorf("expected 1 error, got %d", result.Errors)
	}

	// Verify existing record is preserved with SyncError
	records, _ := agentStore.List(context.Background(), 42)
	if len(records) != 1 {
		t.Fatalf("expected 1 record, got %d", len(records))
	}
	if records[0].ID != existingID {
		t.Errorf("expected ID %q preserved, got %q", existingID, records[0].ID)
	}
	if records[0].Config.Description != "previously valid" {
		t.Errorf("expected preserved config, got %q", records[0].Config.Description)
	}
	if records[0].SyncError == "" {
		t.Error("expected SyncError to be set")
	}
}

func TestReconciler_FullReconcile_HardError_NoExisting_SkipsRecord(t *testing.T) {
	files := &mockFileReader{
		trees: []*sweagentd.SpokesObject{
			{Oid: "oid1", Path: ".github/agents/broken.md"},
		},
		blobs: [][]byte{
			[]byte("broken content"),
		},
	}

	agentStore := memory.NewStore()
	obsv := observability.NewNoopExporters()
	reconciler := NewReconciler(files, obsv)

	event := &SyncEvent{
		Scope:     agentconfig.ScopeRepository,
		ScopeID:   42,
		RepoID:    42,
		CommitSHA: "abc123",
		Directory: RepoAgentsDir,
		ChangedFiles: []ChangedFile{
			{ChangeType: ChangeTypeAddition, CurrentPath: ".github/agents/broken.md"},
		},
	}

	result, err := reconciler.Reconcile(context.Background(), agentStore, event, parseWithHardError)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if result.Errors != 1 {
		t.Errorf("expected 1 error, got %d", result.Errors)
	}

	// With no partial config and no existing record, nothing should be in the store
	records, _ := agentStore.List(context.Background(), 42)
	if len(records) != 0 {
		t.Errorf("expected 0 records, got %d", len(records))
	}
}

func TestReconciler_SyncErrorCleared_OnSuccessfulSync(t *testing.T) {
	files := &mockFileReader{
		trees: []*sweagentd.SpokesObject{
			{Oid: "oid1", Path: ".github/agents/agent-a.md"},
		},
		blobs: [][]byte{
			[]byte(validAgentMarkdown("agent-a")),
		},
	}

	agentStore := memory.NewStore()
	obsv := observability.NewNoopExporters()

	existingID := uuid.NewString()
	_, err := agentStore.Upsert(context.Background(), &store.AgentRecord{
		ID:        existingID,
		ScopeID:   42,
		Path:      ".github/agents/agent-a.md",
		Config:    store.AgentConfig{Name: "agent-a", Description: "partial"},
		SyncError: "previous error",
	})
	if err != nil {
		t.Fatalf("setup error: %v", err)
	}

	reconciler := NewReconciler(files, obsv)
	event := &SyncEvent{
		Scope:     agentconfig.ScopeRepository,
		ScopeID:   42,
		RepoID:    42,
		OwnerID:   100,
		CommitSHA: "fixed123",
		Directory: RepoAgentsDir,
		ChangedFiles: []ChangedFile{
			{ChangeType: ChangeTypeModification, CurrentPath: ".github/agents/agent-a.md"},
			{ChangeType: ChangeTypeAddition, CurrentPath: ".github/agents/other.yml"},
		},
	}

	result, err := reconciler.Reconcile(context.Background(), agentStore, event, simpleParse)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if result.Updated != 1 {
		t.Errorf("expected 1 updated, got %d", result.Updated)
	}

	records, _ := agentStore.List(context.Background(), 42)
	if len(records) != 1 {
		t.Fatalf("expected 1 record, got %d", len(records))
	}
	if records[0].SyncError != "" {
		t.Errorf("expected SyncError to be cleared, got %q", records[0].SyncError)
	}
	if records[0].ID != existingID {
		t.Errorf("expected ID %q preserved, got %q", existingID, records[0].ID)
	}
}

func TestReconciler_ModificationsOnly_ValidationError_UpsertsWithSyncError(t *testing.T) {
	blobByID := map[string][]byte{
		"sha123:.github/agents/agent-a.md": []byte("bad content"),
	}
	files := &mockFileReader{
		blobByID: blobByID,
	}

	agentStore := memory.NewStore()
	obsv := observability.NewNoopExporters()

	existingID := uuid.NewString()
	_, err := agentStore.Upsert(context.Background(), &store.AgentRecord{
		ID:      existingID,
		ScopeID: 42,
		Path:    ".github/agents/agent-a.md",
		Config:  store.AgentConfig{Name: "agent-a", Description: "old valid"},
	})
	if err != nil {
		t.Fatalf("setup error: %v", err)
	}

	reconciler := NewReconciler(files, obsv)
	event := &SyncEvent{
		Scope:     agentconfig.ScopeRepository,
		ScopeID:   42,
		RepoID:    42,
		OwnerID:   100,
		CommitSHA: "sha123",
		Directory: RepoAgentsDir,
		ChangedFiles: []ChangedFile{
			{ChangeType: ChangeTypeModification, CurrentPath: ".github/agents/agent-a.md"},
		},
	}

	result, err := reconciler.Reconcile(context.Background(), agentStore, event, parseWithValidationError)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if result.Errors != 1 {
		t.Errorf("expected 1 error, got %d", result.Errors)
	}

	records, _ := agentStore.List(context.Background(), 42)
	if len(records) != 1 {
		t.Fatalf("expected 1 record, got %d", len(records))
	}
	if records[0].ID != existingID {
		t.Errorf("expected ID %q preserved, got %q", existingID, records[0].ID)
	}
	if records[0].SyncError == "" {
		t.Error("expected SyncError to be set")
	}
	// Partial config should replace old config
	if records[0].Config.Description != "partial config" {
		t.Errorf("expected partial config description, got %q", records[0].Config.Description)
	}
}

func TestBuildAncestors_RepositoryScope(t *testing.T) {
	event := &SyncEvent{
		Scope:      agentconfig.ScopeRepository,
		ScopeID:    42,
		OwnerID:    100,
		BusinessID: 500,
	}

	ancestors := buildAncestors(event)
	if len(ancestors) != 2 {
		t.Fatalf("expected 2 ancestors, got %d", len(ancestors))
	}
	if ancestors[0].Scope != agentconfig.ScopeOrganization || ancestors[0].ScopeID != 100 {
		t.Errorf("expected org ancestor {%s, 100}, got {%s, %d}", agentconfig.ScopeOrganization, ancestors[0].Scope, ancestors[0].ScopeID)
	}
	if ancestors[1].Scope != agentconfig.ScopeEnterprise || ancestors[1].ScopeID != 500 {
		t.Errorf("expected enterprise ancestor {%s, 500}, got {%s, %d}", agentconfig.ScopeEnterprise, ancestors[1].Scope, ancestors[1].ScopeID)
	}
}

func TestBuildAncestors_RepositoryScope_NoEnterprise(t *testing.T) {
	event := &SyncEvent{
		Scope:   agentconfig.ScopeRepository,
		ScopeID: 42,
		OwnerID: 100,
	}

	ancestors := buildAncestors(event)
	if len(ancestors) != 1 {
		t.Fatalf("expected 1 ancestor, got %d", len(ancestors))
	}
	if ancestors[0].Scope != agentconfig.ScopeOrganization || ancestors[0].ScopeID != 100 {
		t.Errorf("expected org ancestor, got {%s, %d}", ancestors[0].Scope, ancestors[0].ScopeID)
	}
}

func TestBuildAncestors_OrganizationScope(t *testing.T) {
	event := &SyncEvent{
		Scope:      agentconfig.ScopeOrganization,
		ScopeID:    100,
		OwnerID:    100,
		BusinessID: 500,
	}

	ancestors := buildAncestors(event)
	if len(ancestors) != 1 {
		t.Fatalf("expected 1 ancestor, got %d", len(ancestors))
	}
	if ancestors[0].Scope != agentconfig.ScopeEnterprise || ancestors[0].ScopeID != 500 {
		t.Errorf("expected enterprise ancestor, got {%s, %d}", ancestors[0].Scope, ancestors[0].ScopeID)
	}
}

func TestBuildAncestors_OrganizationScope_NoEnterprise(t *testing.T) {
	event := &SyncEvent{
		Scope:   agentconfig.ScopeOrganization,
		ScopeID: 100,
		OwnerID: 100,
	}

	ancestors := buildAncestors(event)
	if len(ancestors) != 0 {
		t.Errorf("expected 0 ancestors, got %d", len(ancestors))
	}
}

func TestBuildAncestors_EnterpriseScope(t *testing.T) {
	event := &SyncEvent{
		Scope:      agentconfig.ScopeEnterprise,
		ScopeID:    500,
		BusinessID: 500,
	}

	ancestors := buildAncestors(event)
	if len(ancestors) != 0 {
		t.Errorf("expected 0 ancestors for enterprise scope, got %d", len(ancestors))
	}
}

func TestReconciler_FullReconcile_SetsAncestors(t *testing.T) {
	files := &mockFileReader{
		trees: []*sweagentd.SpokesObject{
			{Oid: "oid1", Path: ".github/agents/agent-a.md"},
		},
		blobs: [][]byte{
			[]byte(validAgentMarkdown("agent-a")),
		},
	}

	agentStore := memory.NewStore()
	obsv := observability.NewNoopExporters()
	reconciler := NewReconciler(files, obsv)

	event := &SyncEvent{
		Scope:      agentconfig.ScopeRepository,
		ScopeID:    42,
		RepoID:     42,
		OwnerID:    100,
		BusinessID: 500,
		CommitSHA:  "abc123",
		Directory:  RepoAgentsDir,
		ChangedFiles: []ChangedFile{
			{ChangeType: ChangeTypeAddition, CurrentPath: ".github/agents/agent-a.md"},
		},
	}

	_, err := reconciler.Reconcile(context.Background(), agentStore, event, simpleParse)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	records, _ := agentStore.List(context.Background(), 42)
	if len(records) != 1 {
		t.Fatalf("expected 1 record, got %d", len(records))
	}
	if len(records[0].Ancestors) != 2 {
		t.Fatalf("expected 2 ancestors, got %d", len(records[0].Ancestors))
	}
	if records[0].Ancestors[0].Scope != agentconfig.ScopeOrganization {
		t.Errorf("expected first ancestor to be organization scope, got %s", records[0].Ancestors[0].Scope)
	}
	if records[0].Ancestors[1].Scope != agentconfig.ScopeEnterprise {
		t.Errorf("expected second ancestor to be enterprise scope, got %s", records[0].Ancestors[1].Scope)
	}
}

func TestReconciler_FullReconcile_CleansDuplicatePathRecords(t *testing.T) {
	// If concurrent reconciliations create two records with the same path
	// but different IDs, a subsequent full reconcile must delete the
	// duplicate so that trigger queries return only one agent.
	files := &mockFileReader{
		trees: []*sweagentd.SpokesObject{
			{Oid: "oid1", Path: ".github/agents/ci-fix.md"},
		},
		blobs: [][]byte{
			[]byte(validAgentMarkdown("ci-fix")),
		},
	}

	agentStore := memory.NewStore()
	obsv := observability.NewNoopExporters()

	// Pre-populate with two records at the same path (simulates a race).
	_, err := agentStore.Upsert(context.Background(), &store.AgentRecord{
		ID:      "dup-id-1",
		ScopeID: 42,
		Path:    ".github/agents/ci-fix.md",
		Config:  store.AgentConfig{Name: "ci-fix"},
	})
	if err != nil {
		t.Fatalf("setup error: %v", err)
	}
	_, err = agentStore.Upsert(context.Background(), &store.AgentRecord{
		ID:      "dup-id-2",
		ScopeID: 42,
		Path:    ".github/agents/ci-fix.md",
		Config:  store.AgentConfig{Name: "ci-fix"},
	})
	if err != nil {
		t.Fatalf("setup error: %v", err)
	}

	// Verify we start with 2 records.
	records, _ := agentStore.List(context.Background(), 42)
	if len(records) != 2 {
		t.Fatalf("expected 2 records before reconcile, got %d", len(records))
	}

	reconciler := NewReconciler(files, obsv)
	event := &SyncEvent{
		Scope:     agentconfig.ScopeRepository,
		ScopeID:   42,
		RepoID:    42,
		CommitSHA: "abc123",
		Directory: RepoAgentsDir,
		ChangedFiles: []ChangedFile{
			{ChangeType: ChangeTypeAddition, CurrentPath: ".github/agents/ci-fix.md"},
		},
	}

	result, err := reconciler.Reconcile(context.Background(), agentStore, event, simpleParse)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	// One record should be updated, the duplicate should be deleted.
	if result.Updated != 1 {
		t.Errorf("expected 1 updated, got %d", result.Updated)
	}
	if result.Deleted != 1 {
		t.Errorf("expected 1 deleted, got %d", result.Deleted)
	}

	// Only one record should remain.
	records, _ = agentStore.List(context.Background(), 42)
	if len(records) != 1 {
		t.Fatalf("expected 1 record after reconcile, got %d", len(records))
	}
}
