package jobs

import (
	"fmt"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	"github.com/github/sweagentd/internal/jobs/customagent"
	"github.com/github/sweagentd/internal/jobs/experiments"
	"github.com/google/uuid"
)

// AssignmentResource represents a resource that is associated with an assignment.
// This can be an issue, pull request, or other resource type.
type AssignmentResource struct {
	ID   string `json:"id"`
	Type string `json:"type"`
}

// Assignment represents a collection of related jobs, and configuration that
// applies to all jobs within the assignment.
//
// IMPORTANT:
//   - New assignments should be created using either the [NewAssignment] or
//     [NewAssignmentWithCustomAgent] functions to ensure proper initialization.
//   - New fields should only be of primitive types, slices, or maps, or structs
//     defined in this package or in leaf packages (e.g. custom agent). Do not import
//     other internal packages here unless absolutely necessary.
type Assignment struct {
	ID          string `json:"id"`
	RepoID      int64  `json:"repo_id"`
	OwnerID     int64  `json:"owner_id"`
	RepoNodeID  string `json:"repo_node_id"`
	OwnerNodeID string `json:"owner_node_id"`

	// AdditionalRepositories is the list of additional repositories that all
	// jobs in this assignment have access to beyond the primary repository.
	// It is propagated to each job created via [Assignment.NewJob].
	AdditionalRepositories []RepositoryRef `json:"additional_repositories,omitempty"`

	PullRequestID     int64                `json:"pull_request_id"`
	PullRequestNumber int                  `json:"pull_request_number"`
	CreatedAt         int64                `json:"created_at"`
	UpdatedAt         int64                `json:"_ts,omitempty"`
	Resources         []AssignmentResource `json:"resources"`

	// DetachedResources are the resources that have been detached from the assignment.
	// This is used to track resources that originally initiated the assignment, but
	// are no longer directly associated with it. For example, unassigned issues.
	DetachedResources    []AssignmentResource               `json:"detached_resources"`
	Experiments          *experiments.AssignmentExperiments `json:"experiments,omitempty"`
	SDKAssignmentContext string                             `json:"sdk_assignment_context,omitempty"`
	ETag                 *azcore.ETag                       `json:"_etag,omitempty"`
	CustomAgent          customagent.DBRecord               `json:"custom_agent"`
	UseAsyncSessions     bool                               `json:"use_async_sessions,omitempty"`
}

// NewAssignment creates a new assignment with the given owner and repository
// IDs, resources, and an empty custom agent.
func NewAssignment(ownerID, repoID int64, ownerNodeID, repoNodeID, ownerName, repoName string, useAsyncSessions bool, resources ...AssignmentResource) *Assignment {
	return newAssignment(ownerID, repoID, ownerNodeID, repoNodeID, ownerName, repoName, useAsyncSessions, customagent.DBRecord{}, resources...)
}

// NewAssignmentWithCustomAgent creates a new assignment with the given owner and
// repository IDs, resources, and custom agent information.
//
//nolint:gocritic // hugeParam: while the params here are larger, passing by pointer adds risk of nil dereference and the function is only used internally with all params readily available.
func NewAssignmentWithCustomAgent(ownerID, repoID int64, ownerNodeID, repoNodeID, ownerName, repoName string, useAsyncSessions bool, agent customagent.DBRecord, resources ...AssignmentResource) *Assignment {
	return newAssignment(ownerID, repoID, ownerNodeID, repoNodeID, ownerName, repoName, useAsyncSessions, agent, resources...)
}

//nolint:gocritic // hugeParam: while the params here are larger, passing by pointer adds risk of nil dereference and the function is only used internally with all params readily available.
func newAssignment(ownerID, repoID int64, ownerNodeID, repoNodeID, ownerName, repoName string, useAsyncSessions bool, agent customagent.DBRecord, resources ...AssignmentResource) *Assignment {
	return &Assignment{
		ID:               GenerateAssignmentID(ownerID, repoID),
		RepoID:           repoID,
		OwnerID:          ownerID,
		RepoNodeID:       repoNodeID,
		OwnerNodeID:      ownerNodeID,
		Resources:        resources,
		CustomAgent:      agent,
		UseAsyncSessions: useAsyncSessions,
	}
}

// GenerateAssignmentID generates a new assignment ID based on the owner ID,
// repository ID, and a new UUID.
func GenerateAssignmentID(ownerID, repoID int64) string {
	uid := uuid.New()
	return fmt.Sprintf("%d-%d-%s", ownerID, repoID, uid)
}

// Persisted returns true if the assignment has been persisted to the database.
func (a *Assignment) Persisted() bool {
	return a.ETag != nil
}

// HasCustomAgent returns true if the job has a custom agent assigned to it.
func (a *Assignment) HasCustomAgent() bool {
	return a.CustomAgent.Name != ""
}

// AddDetachedResources adds the given resources to the assignment's detached
// resources list. This is used when a resource may only be associated with a
// single assignment at a time, but needs to be tracked after being removed from
// the assignment.
func (a *Assignment) AddDetachedResources(resources ...AssignmentResource) {
	a.DetachedResources = append(a.DetachedResources, resources...)
}

// GetRepositoryID returns the repository ID associated with the assignment.
// This method satisfies the [sweagentd.Repository] interface for [Assignment].
func (a *Assignment) GetRepositoryID() int64 {
	return a.RepoID
}

// GetOwnerID returns the owner ID associated with the assignment.
// This method satisfies the [sweagentd.Repository] interface for [Assignment].
func (a *Assignment) GetOwnerID() int64 {
	return a.OwnerID
}
