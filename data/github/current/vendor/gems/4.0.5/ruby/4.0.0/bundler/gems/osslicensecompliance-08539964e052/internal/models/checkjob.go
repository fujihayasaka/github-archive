package models

import (
	"fmt"
	"strings"
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

	// Error means the check encountered an error and could not complete.
	Error
)

// NewCheckStatus converts a string from MySQL values to a CheckStatus value
func NewCheckStatus(s string) CheckStatus {
	switch s {
	case "waiting":
		return Waiting
	case "running":
		return Running
	case "pass":
		return Pass
	case "fail":
		return Fail
	case "error":
		return Error
	default:
		// The default catches the "starting" case.  There _shouldn't_ be any other values,
		// but Starting is a good default because there shouldn't be much harm in getting
		// the process going.
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
	case Error:
		return "error"
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
	ForkRepositoryID  *uint64     `db:"fork_repository_id"`
	HeadRef           *string     `db:"head_ref"`
	BaseSHA           string      `db:"base_sha"`
	CommitSHA         string      `db:"commit_sha"`
	ExpectedSnapshots uint32      `db:"expected_snapshots"`
	ReceivedSnapshots uint32      `db:"received_snapshots"`
	MissingDetectors  []string    `db:"missing_detectors"`
	DependabotPending bool        `db:"dependabot_pending"`
}

// Log message constants for license check progress events.
const (
	//nolint:gosec // G101 false positive - "Pass" refers to check status, not password
	CheckProgressedLogMessagePass        = "✓ License check passed"
	CheckProgressedLogMessageFail        = "✗ License check completed with violations. See the comment from license-compliance-bot on this pull request for details."
	CheckProgressedLogMessageErrorPrefix = "✗ Unable to complete check: "
)

// Title constants for check run results.
const (
	//nolint:gosec // G101 false positive - "Pass" refers to check status, not password
	CheckProgressedTitlePass   = "No new license compliance alerts in code changed by this pull request"
	CheckProgressedTitleError  = "License compliance check encountered an error"
	CheckProgressedTitleFailed = "License check failed"
)

// LogMessage returns the appropriate log message for the current check status.
func (c *CheckJob) LogMessage() string {
	switch c.Status {
	case Starting:
		return "Starting license check..."
	case Waiting:
		waitingForSnapshots := c.ReceivedSnapshots < c.ExpectedSnapshots
		if !waitingForSnapshots && c.DependabotPending {
			return "Waiting for Dependabot graph update jobs to complete."
		}
		msg := fmt.Sprintf("Waiting for dependency snapshots on head (%d/%d received)...", c.ReceivedSnapshots, c.ExpectedSnapshots)
		if len(c.MissingDetectors) > 0 {
			msg += fmt.Sprintf(" Missing snapshots from detectors: %s.", strings.Join(c.MissingDetectors, ", "))
		}
		if c.DependabotPending {
			msg += " Also waiting for Dependabot graph update jobs to complete."
		}
		return msg
	case Running:
		return "Evaluating dependencies against license policy..."
	case Pass:
		return CheckProgressedLogMessagePass
	case Fail:
		return CheckProgressedLogMessageFail
	default:
		return "Unknown status"
	}
}

// Title returns the check run title for terminal statuses (Pass, Fail).
// For Fail status, alertCount determines the title text.
func (c *CheckJob) Title(alertCount int) string {
	switch c.Status {
	case Pass:
		return CheckProgressedTitlePass
	case Fail:
		if alertCount < 1 {
			return CheckProgressedTitleFailed
		}
		if alertCount == 1 {
			return "1 new license compliance alert"
		}
		return fmt.Sprintf("%d new license compliance alerts", alertCount)
	case Error:
		return CheckProgressedTitleError
	default:
		return ""
	}
}
