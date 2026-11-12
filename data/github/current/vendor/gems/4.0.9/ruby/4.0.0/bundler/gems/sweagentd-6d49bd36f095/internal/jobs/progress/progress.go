// Package progress defines the Progress type used to represent progress updates
// from an agent during the execution of a job.
package progress

import (
	"encoding/json"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	"github.com/google/uuid"
)

// Progress represents a progress update from an agent for a job. This can be
// a log, status update, error, or any other information about the job's progress.
//
// IMPORTANT:
//   - New progress updates should be created using either the [jobs.Job.NewProgress]
//     or [jobs.JobSummary.NewProgress] method.
//   - New fields should only be of primitive types, slices, or maps, or structs
//     defined in this package. Do not import other internal packages here unless
//     absolutely necessary.
type Progress struct {
	// ID is the unique identifier for the progress update.
	ID string `json:"id"`

	// JobID is the ID of the job this progress update is associated with.
	JobID string `json:"job_id"`

	// AssignmentID is the ID of the assignment this progress update is associated with.
	AssignmentID string `json:"assignment_id"`

	// RepoID is the GitHub repository ID the assignment, job, and progress
	// update are associated with.
	//
	// The value is copied from the job when the progress update is created, do
	// not set it directly. Persisting the value here enables efficient job and
	// assignment retrieval, creating scoped client tokens, logging, etc.
	RepoID int64 `json:"repo_id"`

	// OwnerID is the GitHub repository's owner ID the assignment, job, and
	// progress update are associated with.
	//
	// The value is copied from the job when the progress update is created, do
	// not set it directly. Persisting the value here enables efficient job and
	// assignment retrieval, creating scoped client tokens, logging, etc.
	OwnerID int64 `json:"owner_id"`

	// Version is the version of the progress update payload schema. This is used
	// in conjunction with namespace to support polymorphic progress update
	// types.
	Version int64 `json:"version"`

	// Namespace is the namespace of the progress update payload schema. This is
	// used in conjunction with version and kind to support polymorphic progress
	// update types.
	//
	// TODO (colbylwilliams): Add example namespaces in documentation.
	Namespace string `json:"namespace"`

	// Kind is the kind of progress update. This is used in conjunction with
	// namespace and version to support polymorphic progress update types.
	//
	// TODO (colbylwilliams): Add example kinds in documentation.
	Kind string `json:"kind"`

	// Content is the JSON serialized content of the progress update. The schema
	// of the content is determined by the namespace, version, and kind fields.
	Content any `json:"content"`

	// CreatedAt is the Unix timestamp when the progress update was created.
	CreatedAt int64 `json:"created_at"`

	// UpdatedAt is the Unix timestamp when the progress update was last updated.
	// This is set by CosmosDB, do not set it directly.
	UpdatedAt int64 `json:"_ts,omitempty"`

	// ETag is the entity tag for the progress update, used for optimistic
	// concurrency.
	// This is set by CosmosDB, do not set it directly.
	ETag *azcore.ETag `json:"_etag,omitempty"`
}

// GetContent deserializes the Content field of the Progress into the specified
// type T. It returns the deserialized content and a boolean indicating whether
// the deserialization was successful.
func GetContent[T any](progress *Progress) (T, bool) {
	var content T
	if progress.Content == nil {
		return content, false
	}

	contentJSON, err := json.Marshal(progress.Content)
	if err != nil {
		return content, false
	}

	err = json.Unmarshal(contentJSON, &content)
	if err != nil {
		return content, false
	}

	return content, true
}

// NewID generates a new unique identifier for a progress update.
func NewID() string {
	uid := uuid.New()
	return uid.String()
}
