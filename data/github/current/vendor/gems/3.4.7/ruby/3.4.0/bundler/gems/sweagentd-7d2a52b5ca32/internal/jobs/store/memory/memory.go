package memory

import (
	"context"
	"errors"
	"fmt"
	"slices"
	"sync"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobs/command"
	db "github.com/github/sweagentd/internal/jobs/store"
	"github.com/github/sweagentd/internal/sweagentd"
	"github.com/google/uuid"
)

// Store is an in-memory implementation of the JobsStore interface.
type Store struct {
	mu          sync.RWMutex
	assignments map[int64]map[int64]map[string]*memoryAssignment
	jobs        map[int64]map[int64]map[string]*memoryJob
	commands    map[string]map[string]map[string]*memoryCommand
}

// Ensure that MemoryStore implements JobStore
var _ db.JobsStore = &Store{}

type memoryAssignment struct {
	*jobs.Assignment
}

type memoryJob struct {
	*jobs.Job
	Result string
}

type memoryCommand struct {
	*command.Command
}

// NewStore creates a new in-memory JobsStore.
func NewStore() *Store {
	return &Store{
		assignments: make(map[int64]map[int64]map[string]*memoryAssignment),
		jobs:        make(map[int64]map[int64]map[string]*memoryJob),
		commands:    make(map[string]map[string]map[string]*memoryCommand),
	}
}

func newETag() *azcore.ETag {
	uid := uuid.New()
	str := fmt.Sprintf("\"%s\"", uid.String())
	etag := azcore.ETag(str)
	return &etag
}

// CreateAssignment creates a new assignment in the database.
func (m *Store) CreateAssignment(ctx context.Context, assignment *jobs.Assignment) (*jobs.Assignment, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	if assignment.ETag == nil {
		assignment.ETag = newETag()
	}

	if assignment.CreatedAt == 0 {
		assignment.CreatedAt = time.Now().Unix()
	}

	if _, ok := m.assignments[assignment.OwnerID]; !ok {
		m.assignments[assignment.OwnerID] = make(map[int64]map[string]*memoryAssignment)
	}

	if _, ok := m.assignments[assignment.OwnerID][assignment.RepoID]; !ok {
		m.assignments[assignment.OwnerID][assignment.RepoID] = make(map[string]*memoryAssignment)
	}

	m.assignments[assignment.OwnerID][assignment.RepoID][assignment.ID] = &memoryAssignment{Assignment: assignment}
	return assignment, nil
}

// GetAssignment retrieves an assignment by its ID.
func (m *Store) GetAssignment(ctx context.Context, owner, repo int64, id string) (*jobs.Assignment, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	assignment, ok := m.assignments[owner][repo][id]
	if !ok {
		return nil, errors.New("assignment not found")
	}
	return assignment.Assignment, nil
}

// GetAssignments retrieves all assignments for a given owner and repository.
func (m *Store) GetAssignments(ctx context.Context, owner, repo int64) ([]*jobs.Assignment, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	assignments := make([]*jobs.Assignment, 0, len(m.assignments[owner][repo]))
	for _, assignment := range m.assignments[owner][repo] {
		assignments = append(assignments, assignment.Assignment)
	}
	return assignments, nil
}

// UpdateAssignment updates an existing assignment in the database.
func (m *Store) UpdateAssignment(ctx context.Context, assignment *jobs.Assignment) (*jobs.Assignment, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	ma, ok := m.assignments[assignment.OwnerID][assignment.RepoID][assignment.ID]
	if !ok {
		return nil, errors.New("assignment not found")
	}

	if assignment.ETag != nil && !ma.ETag.Equals(*assignment.ETag) {
		return nil, db.ErrPreconditionFailedOnUpdate
	}
	assignment.ETag = newETag()

	ma.Assignment = assignment

	return assignment, nil
}

// UpsertAssignment creates or updates an assignment in the database.
func (m *Store) UpsertAssignment(ctx context.Context, assignment *jobs.Assignment) (*jobs.Assignment, error) {
	a, err := m.GetAssignment(ctx, assignment.OwnerID, assignment.RepoID, assignment.ID)
	if err != nil && err.Error() != "assignment not found" {
		return nil, err
	}
	if a == nil {
		return m.CreateAssignment(ctx, assignment)
	}

	if assignment.CreatedAt == 0 {
		assignment.CreatedAt = time.Now().Unix()
	}

	assignment, err = m.UpdateAssignment(ctx, assignment)
	return assignment, err
}

// PatchAssignment patches specific fields on the assignment in the database.
func (m *Store) PatchAssignment(ctx context.Context, assignment *jobs.Assignment, patch db.AssignmentPatch) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	ma, ok := m.assignments[assignment.OwnerID][assignment.RepoID][assignment.ID]
	if !ok {
		return errors.New("assignment not found")
	}

	if patch.PullRequestID != nil {
		assignment.PullRequestID = *patch.PullRequestID
	}
	if patch.PullRequestNumber != nil {
		assignment.PullRequestNumber = *patch.PullRequestNumber
	}
	if patch.Experiments != nil && patch.Experiments.AssignmentContext != "" {
		assignment.Experiments = patch.Experiments
	}

	if assignment.ETag != nil && !ma.ETag.Equals(*assignment.ETag) {
		return db.ErrPreconditionFailedOnUpdate
	}
	assignment.ETag = newETag()

	ma.Assignment = assignment

	return nil
}

// DeleteAssignment deletes an assignment from the database.
func (m *Store) DeleteAssignment(ctx context.Context, owner, repo int64, id string) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	_, ok := m.assignments[owner][repo][id]
	if !ok {
		return errors.New("assignment not found")
	}
	delete(m.assignments[owner][repo], id)
	return nil
}

// GetAssignmentForPR returns the assignment for the pull request id and/or number.
func (m *Store) GetAssignmentForPR(ctx context.Context, owner, repo int64, id *int64, number *int) (*jobs.Assignment, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	for _, assignment := range m.assignments[owner][repo] {
		if id != nil && assignment.PullRequestID == *id {
			return assignment.Assignment, nil
		}
		if number != nil && assignment.PullRequestNumber == *number {
			return assignment.Assignment, nil
		}
	}

	return nil, nil
}

// GetAssignmentForResource retrieves the assignment associated with a specific resource.
func (m *Store) GetAssignmentForResource(ctx context.Context, owner, repo int64, resource jobs.AssignmentResource) (*jobs.Assignment, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	assignments := []*jobs.Assignment{}
	for _, assignment := range m.assignments[owner][repo] {
		for _, r := range assignment.Resources {
			if r.ID == resource.ID && r.Type == resource.Type {
				assignments = append(assignments, assignment.Assignment)
			}
		}
	}
	if len(assignments) == 0 {
		return nil, nil
	}
	if len(assignments) > 1 {
		return nil, errors.New("multiple assignments found for resource")
	}

	return assignments[0], nil
}

// DetachAssignmentResource adds the given resource to the assignment's detached
// resources list and removes it from the active resources list.
func (m *Store) DetachAssignmentResource(ctx context.Context, assignment *jobs.Assignment, resource jobs.AssignmentResource) error {
	assignment, err := m.GetAssignment(ctx, assignment.OwnerID, assignment.RepoID, assignment.ID)
	if err != nil {
		return err
	}

	remove := -1
	for i, r := range assignment.Resources {
		if r.ID == resource.ID && r.Type == resource.Type {
			remove = i
			assignment.DetachedResources = append(assignment.DetachedResources, r)
			break
		}
	}

	if remove == -1 {
		for _, r := range assignment.DetachedResources {
			if r.ID == resource.ID && r.Type == resource.Type {
				return nil // already detached
			}
		}
		return errors.New("resource not found in assignment")
	}

	assignment.Resources = slices.Delete(assignment.Resources, remove, remove+1)
	_, err = m.UpdateAssignment(ctx, assignment)

	if err != nil {
		return err
	}

	return nil
}

// DetachAssignmentResources detaches all resources from the given assignment.
func (m *Store) DetachAssignmentResources(ctx context.Context, assignment *jobs.Assignment) error {
	assignment, err := m.GetAssignment(ctx, assignment.OwnerID, assignment.RepoID, assignment.ID)
	if err != nil {
		return err
	}

	assignment.DetachedResources = append(assignment.DetachedResources, assignment.Resources...)
	assignment.Resources = []jobs.AssignmentResource{}

	_, err = m.UpdateAssignment(ctx, assignment)
	if err != nil {
		return err
	}

	return nil
}

// GetJobsForAssignment retrieves all jobs associated with a specific assignment.
func (m *Store) GetJobsForAssignment(ctx context.Context, assignment *jobs.Assignment) ([]*jobs.Job, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	jobs := []*jobs.Job{}
	for _, job := range m.jobs[assignment.OwnerID][assignment.RepoID] {
		if job.AssignmentID == assignment.ID {
			jobs = append(jobs, job.Job)
		}
	}

	return jobs, nil
}

// GetJobSummariesForAssignmentID retrieves job summaries for a specific assignment ID.
func (m *Store) GetJobSummariesForAssignmentID(ctx context.Context, owner, repo int64, assignmentID string) ([]*jobs.JobSummary, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	jobs := []*jobs.JobSummary{}
	for _, job := range m.jobs[owner][repo] {
		if job.AssignmentID == assignmentID {
			jobs = append(jobs, job.JobSummary())
		}
	}

	return jobs, nil
}

// CreateJob creates a new job in the database.
func (m *Store) CreateJob(ctx context.Context, job *jobs.Job) (*jobs.Job, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	if job.ETag == nil {
		job.ETag = newETag()
	}

	if job.CreatedAt == 0 {
		job.CreatedAt = time.Now().Unix()
	}

	if _, ok := m.jobs[job.OwnerID]; !ok {
		m.jobs[job.OwnerID] = make(map[int64]map[string]*memoryJob)
	}

	if _, ok := m.jobs[job.OwnerID][job.RepoID]; !ok {
		m.jobs[job.OwnerID][job.RepoID] = make(map[string]*memoryJob)
	}

	m.jobs[job.OwnerID][job.RepoID][job.ID] = &memoryJob{Job: job}

	return job, nil
}

// GetJob retrieves a job by its ID.
func (m *Store) GetJob(ctx context.Context, owner, repo int64, id string) (*jobs.Job, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	job, ok := m.jobs[owner][repo][id]
	if !ok {
		return nil, errors.New("job not found")
	}
	return job.Job, nil
}

// GetJobForComputeID retrieves a job by its compute ID.
func (m *Store) GetJobForComputeID(ctx context.Context, owner, repo int64, computeID string) (*jobs.Job, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	for _, job := range m.jobs[owner][repo] {
		if job.ComputeID == computeID {
			return job.Job, nil
		}
	}

	return nil, nil
}

// GetJobForSessionID retrieves a job by its session ID.
func (m *Store) GetJobForSessionID(ctx context.Context, owner, repo int64, sessionID string) (*jobs.Job, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	// Production store returns `nil` when a job cannot be found, mirror that behavior
	if _, ok := m.jobs[owner]; !ok {
		return nil, nil
	}
	if _, ok := m.jobs[owner][repo]; !ok {
		return nil, nil
	}

	for _, job := range m.jobs[owner][repo] {
		if job.SessionID == sessionID {
			return job.Job, nil
		}
	}

	return nil, nil
}

// GetJobForActorOnboarding retrieves a job for actor onboarding by owner, repo, and actor ID.
func (m *Store) GetJobForActorOnboarding(ctx context.Context, owner, repo, actor int64) (*jobs.Job, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	for _, job := range m.jobs[owner][repo] {
		if job.ActorID == actor && job.OnboardingCommentID != 0 {
			return job.Job, nil
		}
	}

	return nil, nil
}

// ListJobsForPullRequestNumber lists all jobs associated with a specific pull request number.
func (m *Store) ListJobsForPullRequestNumber(ctx context.Context, owner, repo int64, prNumber int) ([]*jobs.Job, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	var jobs []*jobs.Job
	jobsForOwner, ok := m.jobs[owner]
	if !ok {
		return jobs, nil
	}

	for _, job := range jobsForOwner[repo] {
		if job.PullRequestNumber == prNumber {
			jobs = append(jobs, job.Job)
		}
	}

	return jobs, nil
}

// GetRunningJobCountForActor returns the count of running jobs for a specific
// actor within a given time window.
func (m *Store) GetRunningJobCountForActor(ctx context.Context, actor int64, window time.Duration) (int, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	minCreatedAt := time.Now().Add(-window).Unix()
	if window <= 0 {
		d := 24 * time.Hour // default to 24 hours
		minCreatedAt = time.Now().Add(-d).Unix()
	}

	running := 0
	for _, ownerJobs := range m.jobs {
		for _, repoJobs := range ownerJobs {
			for _, job := range repoJobs {
				if job.ActorID == actor && job.Status == jobs.JobStatusRunning && job.CreatedAt >= minCreatedAt {
					running++
				}
			}
		}
	}

	return running, nil
}

// GetJobCountByStatusForActor returns the count of jobs by status for a specific
// actor within a given time window.
func (m *Store) GetJobCountByStatusForActor(ctx context.Context, actor int64, window time.Duration) (sweagentd.JobCounts, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	minCreatedAt := time.Now().Add(-window).Unix()
	if window <= 0 {
		d := 24 * time.Hour // default to 24 hours
		minCreatedAt = time.Now().Add(-d).Unix()
	}

	counts := sweagentd.JobCounts{}

	for _, ownerJobs := range m.jobs {
		for _, repoJobs := range ownerJobs {
			for _, job := range repoJobs {
				if job.ActorID == actor && job.CreatedAt >= minCreatedAt {
					switch job.Status {
					case jobs.JobStatusQueued:
						counts.Queued++
					case jobs.JobStatusRunning:
						counts.Running++
					}
				}
			}
		}
	}

	return counts, nil
}

// GetJobs retrieves all jobs for a given owner and repository.
func (m *Store) GetJobs(ctx context.Context, owner, repo int64) ([]*jobs.Job, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	jobs := make([]*jobs.Job, 0, len(m.jobs[owner][repo]))
	for _, job := range m.jobs[owner][repo] {
		jobs = append(jobs, job.Job)
	}

	return jobs, nil
}

// UpdateJob updates an existing job in the database.
func (m *Store) UpdateJob(ctx context.Context, job *jobs.Job) (*jobs.Job, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	mj, ok := m.jobs[job.OwnerID][job.RepoID][job.ID]
	if !ok {
		return nil, errors.New("job not found")
	}

	if job.ETag != nil && !mj.ETag.Equals(*job.ETag) {
		return nil, db.ErrPreconditionFailedOnUpdate
	}
	job.ETag = newETag()

	mj.Job = job
	return job, nil
}

// UpsertJob creates or updates a job in the database.
func (m *Store) UpsertJob(ctx context.Context, job *jobs.Job) (*jobs.Job, error) {
	j, err := m.GetJob(ctx, job.OwnerID, job.RepoID, job.ID)
	if err != nil && err.Error() != "job not found" {
		return nil, err
	}
	if j == nil {
		return m.CreateJob(ctx, job)
	}

	if job.CreatedAt == 0 {
		job.CreatedAt = time.Now().Unix()
	}

	job, err = m.UpdateJob(ctx, job)
	return job, err
}

// DeleteJob deletes a job from the database.
func (m *Store) DeleteJob(ctx context.Context, owner, repo int64, id string) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	_, ok := m.jobs[owner][repo][id]
	if !ok {
		return errors.New("job not found")
	}
	delete(m.jobs[owner][repo], id)
	return nil
}

// PatchJob applies a partial update to a job.
func (m *Store) PatchJob(ctx context.Context, job *jobs.Job, patch db.JobPatch) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	mj, ok := m.jobs[job.OwnerID][job.RepoID][job.ID]
	if !ok {
		return errors.New("job not found")
	}

	if patch.Status != nil {
		job.Status = *patch.Status
	}
	if patch.ComputeID != nil {
		job.ComputeID = *patch.ComputeID
	}
	if patch.CompletedAt != nil {
		job.CompletedAt = *patch.CompletedAt
	}
	if patch.BranchName != nil {
		job.BranchName = *patch.BranchName
	}
	if patch.PullRequestID != nil {
		job.PullRequestID = *patch.PullRequestID
	}
	if patch.PullRequestNumber != nil {
		job.PullRequestNumber = *patch.PullRequestNumber
	}
	if patch.ReplyCommentID != nil {
		job.ReplyCommentID = *patch.ReplyCommentID
	}
	if patch.OnboardingCommentID != nil {
		job.OnboardingCommentID = *patch.OnboardingCommentID
	}
	if patch.SessionID != nil {
		job.SessionID = *patch.SessionID
	}
	if patch.QueuedAt != nil {
		job.QueuedAt = *patch.QueuedAt
	}
	if patch.Error != nil && patch.Error.Message != "" {
		job.Error = patch.Error
	}
	if patch.Experiments != nil && patch.Experiments.AssignmentContext != "" {
		job.Experiments = patch.Experiments
	}

	if job.ETag != nil && !mj.ETag.Equals(*job.ETag) {
		return db.ErrPreconditionFailedOnUpdate
	}
	job.ETag = newETag()

	mj.Job = job

	return nil
}

// CreateCommand creates a new command in the database.
func (m *Store) CreateCommand(ctx context.Context, cmd *command.Command) (*command.Command, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	if cmd.ETag == nil {
		cmd.ETag = newETag()
	}

	if cmd.CreatedAt == 0 {
		cmd.CreatedAt = time.Now().Unix()
	}

	if _, ok := m.commands[cmd.AssignmentID]; !ok {
		m.commands[cmd.AssignmentID] = make(map[string]map[string]*memoryCommand)
	}

	if _, ok := m.commands[cmd.AssignmentID][cmd.JobID]; !ok {
		m.commands[cmd.AssignmentID][cmd.JobID] = make(map[string]*memoryCommand)
	}

	m.commands[cmd.AssignmentID][cmd.JobID][cmd.ID] = &memoryCommand{Command: cmd}

	return cmd, nil
}

// GetCommand retrieves a command by its ID.
func (m *Store) GetCommand(ctx context.Context, assignment, job, id string) (*command.Command, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	cmd, ok := m.commands[assignment][job][id]
	if !ok {
		return nil, errors.New("command not found")
	}
	return cmd.Command, nil
}

// GetCommands retrieves all commands for a given assignment and job.
func (m *Store) GetCommands(ctx context.Context, assignment, job string) ([]*command.Command, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	commands := make([]*command.Command, 0, len(m.commands[assignment][job]))
	for _, cmd := range m.commands[assignment][job] {
		commands = append(commands, cmd.Command)
	}

	return commands, nil
}

// GetCommandsWithStatus retrieves all commands for a given assignment, job, and status.
func (m *Store) GetCommandsWithStatus(ctx context.Context, assignment, job string, status command.Status) ([]*command.Command, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	commands := []*command.Command{}
	for _, cmd := range m.commands[assignment][job] {
		if cmd.Status == status {
			commands = append(commands, cmd.Command)
		}
	}

	return commands, nil
}

// UpdateCommand updates an existing command in the database.
func (m *Store) UpdateCommand(ctx context.Context, cmd *command.Command) (*command.Command, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	mc, ok := m.commands[cmd.AssignmentID][cmd.JobID][cmd.ID]
	if !ok {
		return nil, errors.New("command not found")
	}

	if cmd.ETag != nil && !mc.ETag.Equals(*cmd.ETag) {
		return nil, db.ErrPreconditionFailedOnUpdate
	}
	cmd.ETag = newETag()

	mc.Command = cmd
	return cmd, nil
}

// PatchCommand applies a partial update to a command in the database.
func (m *Store) PatchCommand(ctx context.Context, cmd *command.Command, patch db.CommandPatch) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	mc, ok := m.commands[cmd.AssignmentID][cmd.JobID][cmd.ID]
	if !ok {
		return errors.New("command not found")
	}

	if patch.Status != nil {
		cmd.Status = *patch.Status
	}
	if patch.DeliveredAt != nil {
		cmd.DeliveredAt = *patch.DeliveredAt
	}

	if cmd.ETag != nil && !mc.ETag.Equals(*cmd.ETag) {
		return db.ErrPreconditionFailedOnUpdate
	}
	cmd.ETag = newETag()

	mc.Command = cmd

	return nil
}

// BatchPatchCommands applies a partial update to multiple commands in a single
// transactional batch operation. All commands must belong to the same assignment
// and job. If any command fails to update, none will be updated.
func (m *Store) BatchPatchCommands(ctx context.Context, commands []*command.Command, patch db.CommandPatch) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	if len(commands) == 0 {
		return nil
	}

	// confirm all commands belong to the same assignment and job
	assignmentID := commands[0].AssignmentID
	jobID := commands[0].JobID
	for _, cmd := range commands {
		if cmd.AssignmentID != assignmentID || cmd.JobID != jobID {
			return db.ErrBatchPartitionKeysMismatch
		}
	}

	var errs []error

	for _, cmd := range commands {
		mc, ok := m.commands[cmd.AssignmentID][cmd.JobID][cmd.ID]
		if !ok {
			return errors.New("command not found")
		}

		if patch.Status != nil {
			cmd.Status = *patch.Status
		}
		if patch.DeliveredAt != nil {
			cmd.DeliveredAt = *patch.DeliveredAt
		}

		if cmd.ETag != nil && !mc.ETag.Equals(*cmd.ETag) {
			errs = append(errs, fmt.Errorf("failed to patch command with status: %d", 429))
		} else {
			cmd.ETag = newETag()
			mc.Command = cmd
		}
	}

	if len(errs) > 0 {
		return errors.Join(db.ErrBatchOperationFailed, errors.Join(errs...))
	}

	return nil
}
