package agentsync

import (
	"context"
	"errors"
	"strings"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/sweagentd/internal/agentconfig"
	"github.com/github/sweagentd/internal/customagent/store"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/spokes"
	"github.com/github/sweagentd/internal/sweagentd"
	"github.com/google/uuid"
)

const (
	agentFileExtension     = ".md"
	agentReadmeFile        = "README.md"
	agentLongFileExtension = ".agent.md"
)

// ParseFunc parses file contents into an AgentConfig.
// The path is the file path within the repository, and name is the derived agent name.
type ParseFunc func(path string, contents []byte, name string) (*store.AgentConfig, error)

// Reconciler handles syncing agent files from git to the database.
type Reconciler struct {
	files FileReader
	obsv  observability.Exporters
}

// NewReconciler creates a new Reconciler.
func NewReconciler(files FileReader, obsv observability.Exporters) *Reconciler {
	return &Reconciler{
		files: files,
		obsv:  obsv,
	}
}

// Reconcile fetches agent files from the repository and reconciles them with the store.
// It returns a SyncResult with counts of added, updated, deleted, and errored records.
func (r *Reconciler) Reconcile(ctx context.Context, agentStore AgentStore, event *SyncEvent, parse ParseFunc) (*SyncResult, error) {
	// If all changes are modifications (no adds/deletes/renames), take the fast path
	if event.HasOnlyModifications() {
		return r.reconcileModificationsOnly(ctx, agentStore, event, parse)
	}

	return r.reconcileFull(ctx, agentStore, event, parse)
}

// reconcileFull performs a full reconciliation: list all files from Spokes,
// compare with all records in the store, and upsert/delete as needed.
func (r *Reconciler) reconcileFull(ctx context.Context, agentStore AgentStore, event *SyncEvent, parse ParseFunc) (*SyncResult, error) {
	result := &SyncResult{}

	// 1. Fetch current agent files from Spokes
	repoFiles, treeOID, err := r.listAgentFiles(ctx, event)
	if err != nil {
		return nil, goerrors.Errorf("failed to list agent files: %w", err)
	}

	// Use the OID returned by ListTrees (the resolved default branch commit)
	// as TreeOID, since that reflects the actual revision we read files from.
	effectiveOID := treeOID
	if effectiveOID == "" {
		effectiveOID = event.CommitSHA
	}

	// 2. Read all file contents in a single batch request
	fileContents, err := r.readFileContents(ctx, event, repoFiles)
	if err != nil {
		return nil, goerrors.Errorf("failed to read file contents: %w", err)
	}

	// 3. Get existing records from the store
	existing, err := agentStore.List(ctx, event.ScopeID)
	if err != nil {
		return nil, goerrors.Errorf("failed to list existing records: %w", err)
	}

	// Build lookup map: path -> existing record
	existingByPath := make(map[string]*store.AgentRecord, len(existing))
	for _, rec := range existing {
		existingByPath[rec.Path] = rec
	}

	// 4. Process each file: upsert new/changed records.
	// Track processed record IDs instead of paths so that duplicate records
	// sharing the same path (created by concurrent reconciliations) are
	// cleaned up: only the record referenced by existingByPath survives,
	// and any extra records with the same path but different IDs are
	// deleted as orphans in step 5.
	processedIDs := make(map[string]bool, len(repoFiles))
	for i, file := range repoFiles {
		path := file.Path

		// Mark the existing record for this path as processed so it
		// won't be deleted in the orphan sweep. New files won't have an
		// existing record, and newly-created records aren't in the
		// existing slice, so they don't need tracking here.
		if rec := existingByPath[path]; rec != nil {
			processedIDs[rec.ID] = true
		}

		name := agentNameFromPath(event.Directory, path)
		cfg, parseErr := parse(path, fileContents[i], name)
		if parseErr != nil {
			r.obsv.LoggerWithTelemetry(ctx).Warn("invalid agent config",
				kvp.String("path", path),
				kvp.String("error", parseErr.Error()),
			)
			result.Errors++
			r.upsertSyncError(ctx, agentStore, event, path, name, cfg, existingByPath[path], parseErr, effectiveOID)
			continue
		}

		record := r.buildRecord(event, path, name, cfg, existingByPath[path])
		record.TreeOID = effectiveOID

		_, err := agentStore.Upsert(ctx, record)
		if err != nil {
			r.obsv.LoggerWithTelemetry(ctx).Error("failed to upsert agent record",
				kvp.String("path", path),
				kvp.String("error", err.Error()),
			)
			result.Errors++
			continue
		}

		if existingByPath[path] != nil {
			result.Updated++
		} else {
			result.Added++
		}
	}

	// 5. Delete orphaned records (records no longer matching a current file).
	// Using ID-based matching ensures that duplicate records sharing the
	// same path are also cleaned up — only the one referenced by
	// existingByPath was marked as processed above.
	for _, rec := range existing {
		if !processedIDs[rec.ID] {
			err := agentStore.Delete(ctx, event.ScopeID, rec.ID)
			if err != nil {
				r.obsv.LoggerWithTelemetry(ctx).Error("failed to delete orphaned record",
					kvp.String("path", rec.Path),
					kvp.String("id", rec.ID),
					kvp.String("error", err.Error()),
				)
				result.Errors++
				continue
			}
			result.Deleted++
		}
	}

	return result, nil
}

// reconcileModificationsOnly handles the optimized case where all changes are
// modifications. It skips the full directory listing and only fetches/updates
// the modified files.
func (r *Reconciler) reconcileModificationsOnly(ctx context.Context, agentStore AgentStore, event *SyncEvent, parse ParseFunc) (*SyncResult, error) {
	result := &SyncResult{}

	// Fetch existing records once up-front to avoid per-file List calls
	existing, err := agentStore.List(ctx, event.ScopeID)
	if err != nil {
		return nil, goerrors.Errorf("failed to list existing records: %w", err)
	}
	existingByPath := make(map[string]*store.AgentRecord, len(existing))
	for _, rec := range existing {
		existingByPath[rec.Path] = rec
	}

	dirPrefix := event.Directory + "/"

	for _, cf := range event.ChangedFiles {
		path := cf.CurrentPath
		if !strings.HasPrefix(path, dirPrefix) || !isAgentFile(path) {
			continue
		}

		contents, err := r.files.ReadBlobByObjectIDPath(ctx, uint64(event.RepoID), event.CommitSHA, path)
		if err != nil {
			r.obsv.LoggerWithTelemetry(ctx).Error("failed to read modified file",
				kvp.String("path", path),
				kvp.String("error", err.Error()),
			)
			result.Errors++
			continue
		}

		name := agentNameFromPath(event.Directory, path)
		cfg, parseErr := parse(path, contents, name)
		if parseErr != nil {
			r.obsv.LoggerWithTelemetry(ctx).Warn("invalid agent config",
				kvp.String("path", path),
				kvp.String("error", parseErr.Error()),
			)
			result.Errors++
			r.upsertSyncError(ctx, agentStore, event, path, name, cfg, existingByPath[path], parseErr, event.CommitSHA)
			continue
		}

		existingRecord := existingByPath[path]
		record := r.buildRecord(event, path, name, cfg, existingRecord)
		_, err = agentStore.Upsert(ctx, record)
		if err != nil {
			r.obsv.LoggerWithTelemetry(ctx).Error("failed to upsert modified record",
				kvp.String("path", path),
				kvp.String("error", err.Error()),
			)
			result.Errors++
			continue
		}
		if existingRecord != nil {
			result.Updated++
		} else {
			result.Added++
		}
	}

	return result, nil
}

// listAgentFiles lists all agent markdown files in the repository directory.
// It returns the files and the resolved commit OID from ListTrees.
// If the directory does not exist (e.g., all agent files were deleted),
// it returns an empty list so the caller can proceed to delete orphaned records.
func (r *Reconciler) listAgentFiles(ctx context.Context, event *SyncEvent) ([]*sweagentd.SpokesObject, string, error) {
	dirPrefix := event.Directory + "/"
	files, oid, err := r.files.ListTrees(ctx, uint64(event.RepoID), dirPrefix)
	if err != nil {
		// When the agents directory doesn't exist (all files deleted, or never
		// created), Spokes returns ErrNotFound. Treat this as an empty list so
		// reconciliation can proceed and clean up orphaned DB records.
		if errors.Is(err, spokes.ErrNotFound) {
			return nil, "", nil
		}
		return nil, "", err
	}

	// Filter to only agent files, normalizing paths to repo-root-relative form.
	// ListTrees may return paths relative to the listed directory (e.g.,
	// "my-agent.md" instead of ".github/agents/my-agent.md"). Normalize to
	// full paths to stay consistent with reconcileModificationsOnly, which
	// uses Hydro's repo-root-relative paths (ChangedFile.CurrentPath).
	agentFiles := make([]*sweagentd.SpokesObject, 0, len(files))
	for _, f := range files {
		path := f.Path
		if !strings.HasPrefix(path, dirPrefix) {
			path = dirPrefix + path
		}
		if isAgentFile(path) {
			agentFiles = append(agentFiles, &sweagentd.SpokesObject{
				Oid:  f.Oid,
				Path: path,
			})
		}
	}
	return agentFiles, oid, nil
}

// readFileContents reads all file contents in a single batch request.
func (r *Reconciler) readFileContents(ctx context.Context, event *SyncEvent, files []*sweagentd.SpokesObject) ([][]byte, error) {
	if len(files) == 0 {
		return nil, nil
	}

	oids := make([]string, len(files))
	for i, f := range files {
		oids[i] = f.Oid
	}

	return r.files.ReadBlobObjects(ctx, uint64(event.RepoID), oids)
}

// buildRecord creates or updates an AgentRecord from the parsed config.
func (r *Reconciler) buildRecord(event *SyncEvent, path, name string, cfg *store.AgentConfig, existing *store.AgentRecord) *store.AgentRecord {
	record := &store.AgentRecord{
		ScopeID:   event.ScopeID,
		Path:      path,
		Config:    *cfg,
		TreeOID:   event.CommitSHA,
		Ancestors: buildAncestors(event),
		// SyncError is intentionally left empty to clear any previous error
		// when the config parses successfully.
	}

	if existing != nil {
		// Preserve the existing ID and creation timestamp
		record.ID = existing.ID
		record.CreatedAt = existing.CreatedAt
	} else {
		record.ID = uuid.NewString()
	}

	// Set the config name from the parsed name if not already set
	if record.Config.Name == "" {
		record.Config.Name = name
	}

	return record
}

// upsertSyncError creates or updates a record with SyncError set when config
// parsing fails. If partialCfg is non-nil (validation error with partial config),
// it is used as the record's config. Otherwise, the existing record's config is
// preserved. If neither is available, no record is created.
func (r *Reconciler) upsertSyncError(
	ctx context.Context,
	agentStore AgentStore,
	event *SyncEvent,
	path, name string,
	partialCfg *store.AgentConfig,
	existing *store.AgentRecord,
	parseErr error,
	treeOID string,
) {
	var record *store.AgentRecord

	switch {
	case partialCfg != nil:
		record = r.buildRecord(event, path, name, partialCfg, existing)
	case existing != nil:
		record = r.buildRecord(event, path, name, &existing.Config, existing)
	default:
		return
	}

	record.SyncError = parseErr.Error()
	record.TreeOID = treeOID

	_, err := agentStore.Upsert(ctx, record)
	if err != nil {
		r.obsv.LoggerWithTelemetry(ctx).Error("failed to upsert sync error record",
			kvp.String("path", path),
			kvp.String("error", err.Error()),
		)
	}
}

// buildAncestors constructs the ancestor scope hierarchy for an agent record.
func buildAncestors(event *SyncEvent) []store.AgentAncestor {
	var ancestors []store.AgentAncestor

	switch event.Scope {
	case agentconfig.ScopeRepository:
		if event.OwnerID != 0 {
			ancestors = append(ancestors, store.AgentAncestor{
				Scope:   agentconfig.ScopeOrganization,
				ScopeID: event.OwnerID,
			})
		}
		if event.BusinessID != 0 {
			ancestors = append(ancestors, store.AgentAncestor{
				Scope:   agentconfig.ScopeEnterprise,
				ScopeID: event.BusinessID,
			})
		}
	case agentconfig.ScopeOrganization:
		if event.BusinessID != 0 {
			ancestors = append(ancestors, store.AgentAncestor{
				Scope:   agentconfig.ScopeEnterprise,
				ScopeID: event.BusinessID,
			})
		}
	default:
		// Enterprise and unknown scopes have no ancestors.
	}

	return ancestors
}

// isAgentFile returns true if the file path is a valid agent config file.
func isAgentFile(path string) bool {
	if !strings.HasSuffix(path, agentFileExtension) {
		return false
	}
	// Skip README files
	if strings.HasSuffix(path, agentReadmeFile) {
		return false
	}
	return true
}

// agentNameFromPath extracts the agent name from a file path.
// e.g., ".github/agents/my-agent.md" -> "my-agent"
// e.g., ".github/agents/my-agent.agent.md" -> "my-agent"
func agentNameFromPath(directory, path string) string {
	name := strings.TrimPrefix(path, directory+"/")
	if trimmed, found := strings.CutSuffix(name, agentLongFileExtension); found {
		return trimmed
	}
	return strings.TrimSuffix(name, agentFileExtension)
}
