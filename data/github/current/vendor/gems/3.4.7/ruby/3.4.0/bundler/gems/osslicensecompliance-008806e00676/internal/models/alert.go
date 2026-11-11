package models

import (
	"database/sql"
	"fmt"
	"strings"
	"time"

	"github.com/github/osslicensecompliance/pkg/proto/v0"
)

// AlertStatus represents the status of a license compliance alert on a package.
type AlertStatus int

const (
	// Open is the initial state that indicates the alert hasn't been actioned yet.
	Open AlertStatus = iota

	// ReviewRequested is an open state that indicates that a review has been requested for the alert by a user/dev.
	ReviewRequested

	// ReviewDenied is an open state that indicates that a request for review has been denied by a reviewer.
	ReviewDenied

	// Closed indicates that the alert has been resolved (e.g. due to an exception added, policy change, dependency fix etc.).
	Closed
)

// AlertResolution describes how the alert was resolved
type AlertResolution int

const (
	// ExceptionAdded indicates the alert has been resolved by adding a package exception to the policy.
	ExceptionAdded AlertResolution = iota

	// PolicyChanged indicates the alert has been resolved by a policy change.
	PolicyChanged

	// Unknown indicates cases where the alert was resolved but the specific resolution could not be determined.
	Unknown
)

// String provides a string representation of the AlertStatus that matches the MySQL values.
func (a AlertStatus) String() string {
	switch a {
	case Open:
		return "open"
	case ReviewRequested:
		return "review_requested"
	case ReviewDenied:
		return "review_denied"
	case Closed:
		return "closed"
	default:
		panic(fmt.Sprintf("invalid alert status: %d", a))
	}
}

func (r AlertResolution) String() string {
	switch r {
	case ExceptionAdded:
		return "exception_added"
	case PolicyChanged:
		return "policy_changed"
	case Unknown:
		return "unknown"
	default:
		panic(fmt.Sprintf("invalid alert resolution: %d", r))
	}
}

// AlertStatusFromString converts a string (from DB) into an AlertStatus enum value.
// Defaults to Open if the status string is unrecognized.
func AlertStatusFromString(s string) AlertStatus {
	switch s {
	case "open":
		return Open
	case "closed":
		return Closed
	case "review_requested":
		return ReviewRequested
	case "review_denied":
		return ReviewDenied
	default:
		return Open
	}
}

// AlertResolutionPtrFromString converts a string (from DB) into a AlertResolution enum value.
// Defaults to nil if the resolution string is unrecognized.
func AlertResolutionPtrFromString(s string) *AlertResolution {
	switch s {
	case "exception_added":
		r := ExceptionAdded
		return &r
	case "policy_changed":
		r := PolicyChanged
		return &r
	case "unknown":
		r := Unknown
		return &r
	default:
		return nil
	}
}

// Alert represents a license compliance alert for a package in a repository.
type Alert struct {
	ID                    uint64               `db:"id"`
	Number                uint32               `db:"number"`
	Status                AlertStatus          `db:"status"`
	Resolution            *AlertResolution     `db:"resolution"`
	CreatedAt             time.Time            `db:"created_at"`
	RepositoryID          uint64               `db:"repository_id"`
	OrganizationID        uint64               `db:"organization_id"`
	EnterpriseID          *uint64              `db:"enterprise_id"`
	ManifestName          string               `db:"manifest_name"`
	ManifestLineNumber    uint32               `db:"manifest_line_number"`
	PackageEcosystem      proto.PackageManager `db:"package_ecosystem"`
	PackageName           string               `db:"package_name"`
	PackageVersion        string               `db:"package_version"`
	SPDXLicenseExpression string               `db:"spdx_license_expression"`
	PullRequestNumber     *uint32              `db:"pull_request_number"`
}

// SetStatusAndResolution sets the status and resolution fields on an alert from database values.
func (a *Alert) SetStatusAndResolution(status string, resolution sql.NullString) {
	a.Status = AlertStatusFromString(status)
	if resolution.Valid {
		a.Resolution = AlertResolutionPtrFromString(resolution.String)
	} else {
		a.Resolution = nil
	}
}

const prefixLength = len("PACKAGE_MANAGER_")

// PackageManagerToString converts a proto.PackageManager to a human-friendly string.
func PackageManagerToString(pm proto.PackageManager) string {
	// A human-readable form can be made by stripping the "PACKAGE_MANAGER_" prefix
	// and making it lower case.
	return strings.ToLower(pm.String()[prefixLength:])
}

// CompareAlertsByScope compares two alerts for sorting by enterprise, organization, then repository.
// Returns -1 if a < b, 0 if a == b, 1 if a > b.
// nil enterprise IDs are treated as 0 and sorted first.
func CompareAlertsByScope(a, b *Alert) int {
	aEnterprise := uint64(0)
	if a.EnterpriseID != nil {
		aEnterprise = *a.EnterpriseID
	}
	bEnterprise := uint64(0)
	if b.EnterpriseID != nil {
		bEnterprise = *b.EnterpriseID
	}

	if aEnterprise != bEnterprise {
		if aEnterprise < bEnterprise {
			return -1
		}
		return 1
	}

	if a.OrganizationID != b.OrganizationID {
		if a.OrganizationID < b.OrganizationID {
			return -1
		}
		return 1
	}

	if a.RepositoryID != b.RepositoryID {
		if a.RepositoryID < b.RepositoryID {
			return -1
		}
		return 1
	}

	return 0
}
