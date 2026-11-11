package models

import (
	"fmt"
	"time"
)

// CheckStatus is the internal status of a license check job.
// We always return pass/fail/pending to the rule, but internally we
// keep track of where we are in the process.
type CheckStatus int

const (
	// Starting is the start of the process, which involves a
	// background goroutine asking DS-API for snapshot counts
	// for the PR SHA and base SHA. That way we know if we
	// have to go to Waiting state (because there are snapshots
	// expected) or if we can go straight to the Running state.
	Starting CheckStatus = iota

	// Waiting means that we're waiting for snapshots to be ready.
	Waiting

	// Running means that we're calling DG-API's diff endpoint to
	// compare the base and PR branch dependencies so that we
	// can perform the license check.
	Running

	// Pass means the check is complete and passed.
	Pass

	// Fail means the check is complete and failed.
	Fail
)

// NewCheckStatus converts a string from MySQL values to a CheckStatus value
func NewCheckStatus(s string) CheckStatus {
	switch s {
	case "starting":
		return Starting
	case "waiting":
		return Waiting
	case "running":
		return Running
	case "pass":
		return Pass
	case "fail":
		return Fail
	default:
		// This _shouldn't_ happen, but Starting is a good default because there
		// shouldn't be much harm in getting the process going.
		return Starting
	}
}

// String provides a string representation of the CheckStatus that
// matches the MySQL enum.
func (c CheckStatus) String() string {
	switch c {
	case Starting:
		return "starting"
	case Waiting:
		return "waiting"
	case Running:
		return "running"
	case Pass:
		return "pass"
	case Fail:
		return "fail"
	default:
		panic(fmt.Sprintf("invalid check status: %d", c))
	}
}

// CheckJob represents a license check job for a pull request.
type CheckJob struct {
	ID                uint64      `db:"id"`
	Status            CheckStatus `db:"status"`
	CreatedAt         time.Time   `db:"created_at"`
	CheckStartedAt    time.Time   `db:"check_started_at"`
	RepositoryID      uint64      `db:"repository_id"`
	OrganizationID    uint64      `db:"organization_id"`
	PullRequestID     uint64      `db:"pull_request_id"`
	PullRequestNumber uint32      `db:"pull_request_number"`
	EnterpriseID      *uint64     `db:"enterprise_id"`
	BaseSHA           string      `db:"base_sha"`
	CommitSHA         string      `db:"commit_sha"`
	ExpectedSnapshots uint32      `db:"expected_snapshots"`
	ReceivedSnapshots uint32      `db:"received_snapshots"`
}
