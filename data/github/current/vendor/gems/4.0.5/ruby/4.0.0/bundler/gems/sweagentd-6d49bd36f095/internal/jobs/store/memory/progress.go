package memory

import (
	"context"
	"slices"
	"time"

	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/jobs/progress"
	"github.com/github/sweagentd/internal/jobs/store"
)

// CreateProgress creates a new progress update in the database.
func (m *Store) CreateProgress(ctx context.Context, p *progress.Progress) (*progress.Progress, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	if p.ETag == nil {
		p.ETag = newETag()
	}

	if p.CreatedAt == 0 {
		p.CreatedAt = time.Now().Unix()
	}

	if _, ok := m.progress[p.AssignmentID]; !ok {
		m.progress[p.AssignmentID] = make(map[string]map[string]*memoryProgress)
	}

	if _, ok := m.progress[p.AssignmentID][p.JobID]; !ok {
		m.progress[p.AssignmentID][p.JobID] = make(map[string]*memoryProgress)
	}

	m.progress[p.AssignmentID][p.JobID][p.ID] = &memoryProgress{Progress: p}

	return p, nil
}

// GetProgress retrieves a progress update by its ID.
func (m *Store) GetProgress(ctx context.Context, assignment, job, id string) (*progress.Progress, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	p, ok := m.progress[assignment][job][id]
	if !ok {
		return nil, goerrors.New("progress update not found")
	}
	return p.Progress, nil
}

// BatchCreateProgress creates multiple progress updates in a single operation.
func (m *Store) BatchCreateProgress(ctx context.Context, progresses []*progress.Progress) ([]*progress.Progress, error) {
	if len(progresses) == 0 {
		return progresses, nil
	}

	// confirm all items belong to the same assignment and job
	assignmentID := progresses[0].AssignmentID
	jobID := progresses[0].JobID
	for _, cmd := range progresses {
		if cmd.AssignmentID != assignmentID || cmd.JobID != jobID {
			return nil, store.NewErrBatchPartitionKeysMismatch()
		}
	}

	m.mu.Lock()
	defer m.mu.Unlock()
	if _, ok := m.progress[assignmentID]; !ok {
		m.progress[assignmentID] = make(map[string]map[string]*memoryProgress)
	}
	if _, ok := m.progress[assignmentID][jobID]; !ok {
		m.progress[assignmentID][jobID] = make(map[string]*memoryProgress)
	}

	for _, p := range progresses {
		if p.ETag == nil {
			p.ETag = newETag()
		}
		if p.CreatedAt == 0 {
			p.CreatedAt = time.Now().Unix()
		}
		m.progress[assignmentID][jobID][p.ID] = &memoryProgress{Progress: p}
	}

	return progresses, nil
}

// ListProgress retrieves all progress updates for a given assignment and job.
func (m *Store) ListProgress(ctx context.Context, assignment, job string) ([]*progress.Progress, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	all := make([]*progress.Progress, 0, len(m.progress[assignment][job]))
	for _, p := range m.progress[assignment][job] {
		all = append(all, p.Progress)
	}

	return all, nil
}

// ListProgressByNamespace retrieves all progress updates for a given
// assignment, job, and namespace.
func (m *Store) ListProgressByNamespace(ctx context.Context, assignment, job string, namespaces []string) ([]*progress.Progress, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	all := []*progress.Progress{}
	for _, p := range m.progress[assignment][job] {
		if slices.Contains(namespaces, p.Namespace) {
			all = append(all, p.Progress)
		}
	}

	return all, nil
}

// ListProgressByNamespaceAndKind retrieves all progress updates for a given
// assignment, job, namespace, and kind.
func (m *Store) ListProgressByNamespaceAndKind(ctx context.Context, assignment, job, namespace, kind string) ([]*progress.Progress, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	all := []*progress.Progress{}
	for _, p := range m.progress[assignment][job] {
		if p.Namespace == namespace && p.Kind == kind {
			all = append(all, p.Progress)
		}
	}

	return all, nil
}

// UpdateProgress updates an existing progress update in the database.
func (m *Store) UpdateProgress(ctx context.Context, cmd *progress.Progress) (*progress.Progress, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	mp, ok := m.progress[cmd.AssignmentID][cmd.JobID][cmd.ID]
	if !ok {
		return nil, goerrors.New("progress update not found")
	}

	if cmd.ETag != nil && !mp.ETag.Equals(*cmd.ETag) {
		return nil, store.NewErrPreconditionFailedOnUpdate()
	}
	cmd.ETag = newETag()

	mp.Progress = cmd
	return cmd, nil
}
