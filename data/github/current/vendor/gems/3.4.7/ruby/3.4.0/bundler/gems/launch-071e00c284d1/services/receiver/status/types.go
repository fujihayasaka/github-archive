package status

import (
	"encoding/json"
	"time"
)

type WorkflowID string

type JobID string

type GateID string

// JobStatusUpdateRequest is the incoming JSON from AZP.
type JobStatusUpdateRequest struct {
	Name         string        `json:"name"`        // Name of the  job in the UI
	ExternalID   string        `json:"external_id"` // External ID from AZP
	Number       int64         `json:"number"`      // Zero-based index in a topological sort of jobs
	CompletedLog *CompletedLog `json:"completed_log"`
	Artifacts    []Artifact    `json:"artifacts"`
	LogStream    *LogStream    `json:"log_stream"`
	Steps        []Step        `json:"steps"`
	JobKey       string        `json:"job_key"`
	Runtime      struct {
		Name             string           `json:"name"`
		Version          string           `json:"version"`
		SelfHosted       bool             `json:"self_hosted"`
		Labels           []string         `json:"labels"`
		RunnerID         int64            `json:"runner_id"`
		RunnerName       string           `json:"runner_name"`
		RunnerGroupID    int64            `json:"runner_group_id"`
		RunnerGroupName  string           `json:"runner_group_name"`
		RunnerProperties *json.RawMessage `json:"runner_properties"` // Generic JSON object of random properties
		RunnerType       *string          `json:"runner_type"`
	} `json:"runtime"`
	DurationMs              int64        `json:"duration_ms"`
	Progress                             // Fields for progress
	Annotations             []Annotation `json:"annotations"`
	Delayed                 bool         `json:"delayed"`
	ParentJobID             string       `json:"parent_job_id"`
	Environment             *Environment `json:"environment"`
	Concurrency             *Concurrency `json:"concurrency"`
	IsClonedFromPreviousRun bool         `json:"is_cloned_from_previous_run"`
	SummaryURL              *string      `json:"summary_url"`
	BillableOwnerID         string       `json:"billable_owner_id"`
	CustomerID              int64        `json:"customer_id"`
	QueuedAt                time.Time    `json:"queued_at"`
	ProductSku              string       `json:"product_sku"`
}

type RunStatusUpdateRequest struct {
	CompletedLog *CompletedLog `json:"completed_log"`
	Artifacts    []Artifact    `json:"artifacts"`
	Progress                   // Fields for progress
	Annotations  []Annotation  `json:"annotations"`
	StartedAt    *time.Time    `json:"started_at"`
	CompletedAt  *time.Time    `json:"completed_at"`
	ExpiresAt    *time.Time    `json:"expires_at"`
	Concurrency  *Concurrency  `json:"concurrency"`
}

// Step is one step of a job.
type Step struct {
	Name         string        `json:"name"`          // Name of the Step
	ExternalID   string        `json:"external_id"`   // External ID from AZP
	Number       int64         `json:"number"`        // Zero-based index in the list of steps
	CompletedLog *CompletedLog `json:"completed_log"` // URL to fetch the completed log output
	Progress                   // Fields for progress
}

// Progress has fields that apply to the top level JobStatusUpdateRequest
// and an individual Step.
type Progress struct {
	Status      string    `json:"status"`
	StartedAt   time.Time `json:"started_at"`
	Conclusion  *string   `json:"conclusion"`
	CompletedAt time.Time `json:"completed_at"`
}

// Artifact is an output of a job run.
type Artifact struct {
	Name      string    `json:"name"`
	Size      int64     `json:"size"`
	URL       string    `json:"source_url"`
	CreatedAt time.Time `json:"created_at"`
	ExpiresAt time.Time `json:"expires_at"`
}

// Annotation represents an annotation to be created
type Annotation struct {
	AnnotationLevel string `json:"annotation_level"`
	Message         string `json:"message"`
	RawDetails      string `json:"raw_details"`
	Path            string `json:"path"`
	Title           string `json:"title"`
	StartLine       int64  `json:"start_line"`
	EndLine         int64  `json:"end_line"`
	StartColumn     int64  `json:"start_column"`
	EndColumn       int64  `json:"end_column"`
	StepNumber      int64  `json:"step_number"`
}

// CompletedLog is the output for a job's completed logs.
type CompletedLog struct {
	URL       string    `json:"url"`   // URL pointing to the log
	Lines     int64     `json:"lines"` // Number of lines in the logs
	CreatedAt time.Time `json:"created_at"`
}

// LogStream allows access to a streaming log.
type LogStream struct {
	URL            string    `json:"url"`              // URL for the log stream
	Token          string    `json:"token"`            // An auth token for the log stream
	TokenExpiresAt time.Time `json:"token_expires_at"` // An expiration time for the log stream token
}

// Job has an Environment
type Environment struct {
	Name string `json:"name"` // Name of the Environment
	URL  string `json:"url"`  // Url of the Environment
}

// Concurrency is an output of a Job
type Concurrency struct {
	Group             string             `json:"group"`               // Group the job is waiting on
	WaitingOnResource *WaitingOnResource `json:"waiting_on_resource"` // optional information to support billing level concurrency
}

// WaitingOnResource is optional information to support billing level concurrency
type WaitingOnResource struct {
	RunExternalID string `json:"run_external_id"` // External ID of run
	JobExternalID string `json:"job_external_id"` // External ID of job
	Identifier    string `json:"identifier"`      // Identifier of job
}

// IsCompleted is true if the status is "completed"
func (jsu JobStatusUpdateRequest) IsCompleted() bool {
	return jsu.Status == "completed"
}

// IsStarted is true if the step has a StartedAt time.
func (s Step) IsStarted() bool {
	return !s.StartedAt.IsZero()
}

// IsCompleted is true if the step has a CompletedAt time.
func (s Step) IsCompleted() bool {
	return !s.CompletedAt.IsZero()
}
