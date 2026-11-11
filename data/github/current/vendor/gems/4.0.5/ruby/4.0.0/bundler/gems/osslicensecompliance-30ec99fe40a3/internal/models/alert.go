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
	// AlertStatusOpen is the initial state that indicates the alert hasn't been actioned yet.
	AlertStatusOpen AlertStatus = iota

	// AlertStatusReviewRequested is an open state that indicates that a review has been requested for the alert by a user/dev.
	AlertStatusReviewRequested

	// AlertStatusReviewDenied is an open state that indicates that a request for review has been denied by a reviewer.
	AlertStatusReviewDenied

	// AlertStatusClosed indicates that the alert has been resolved (e.g. due to an exception added, policy change, dependency fix etc.).
	AlertStatusClosed
)

// AlertResolution describes how the alert was resolved
type AlertResolution int

const (
	// AlertResolutionUnknown indicates cases where the alert was resolved but the specific resolution could not be determined.
	AlertResolutionUnknown AlertResolution = iota

	// AlertResolutionExceptionAdded indicates the alert has been resolved by adding a package exception to the policy.
	AlertResolutionExceptionAdded

	// AlertResolutionOutdated indicates the alert has been resolved because the dependency is no longer present.
	AlertResolutionOutdated

	// AlertResolutionLicensesAdded indicates the alert has been resolved by licenses being added to the policy.
	AlertResolutionLicensesAdded
)

// String provides a string representation of the AlertStatus that matches the MySQL values.
func (a AlertStatus) String() string {
	switch a {
	case AlertStatusOpen:
		return "open"
	case AlertStatusReviewRequested:
		return "review_requested"
	case AlertStatusReviewDenied:
		return "review_denied"
	case AlertStatusClosed:
		return "closed"
	default:
		panic(fmt.Sprintf("invalid alert status: %d", a))
	}
}

func (r AlertResolution) String() string {
	switch r {
	case AlertResolutionExceptionAdded:
		return "exception_added"
	case AlertResolutionUnknown:
		return "unknown"
	case AlertResolutionOutdated:
		return "outdated"
	case AlertResolutionLicensesAdded:
		return "licenses_added"
	default:
		panic(fmt.Sprintf("invalid alert resolution: %d", r))
	}
}

// AlertStatusFromString converts a string (from DB) into an AlertStatus enum value.
// Defaults to Open if the status string is unrecognized.
func AlertStatusFromString(s string) AlertStatus {
	switch s {
	case "closed":
		return AlertStatusClosed
	case "review_requested":
		return AlertStatusReviewRequested
	case "review_denied":
		return AlertStatusReviewDenied
	default:
		// This is the case for "open" and any unrecognized values.
		return AlertStatusOpen
	}
}

// AlertResolutionFromString converts a string (from DB) into a AlertResolution enum value.
// Defaults to Unknown if the resolution string is unrecognized.
func AlertResolutionFromString(s string) AlertResolution {
	switch s {
	case "exception_added":
		return AlertResolutionExceptionAdded
	case "outdated":
		return AlertResolutionOutdated
	case "licenses_added":
		return AlertResolutionLicensesAdded
	default:
		// This is the case for "unknown" and any unrecognized values.
		return AlertResolutionUnknown
	}
}

// Alert represents a license compliance alert for a package in a repository.
type Alert struct {
	ID                    uint64               `db:"id"`
	Number                uint32               `db:"number"`
	Status                AlertStatus          `db:"status"`
	Resolution            AlertResolution      `db:"resolution"`
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
	PackageRepoNWO        string               `db:"package_repo_nwo"`
	ClosureReason         *string              `db:"dismissal_reason"`
}

// SetStatusAndResolution sets the status and resolution fields on an alert from database values.
func (a *Alert) SetStatusAndResolution(status string, resolution sql.NullString) {
	a.Status = AlertStatusFromString(status)
	if resolution.Valid {
		a.Resolution = AlertResolutionFromString(resolution.String)
	} else {
		a.Resolution = AlertResolutionUnknown
	}
}

const prefixLength = len("PACKAGE_MANAGER_")

// PackageManagerToString converts a proto.PackageManager to a human-friendly string.
func PackageManagerToString(pm proto.PackageManager) string {
	// A human-readable form can be made by stripping the "PACKAGE_MANAGER_" prefix
	// and making it lower case.
	return strings.ToLower(pm.String()[prefixLength:])
}

const (
	// ClosureReasonAmendment indicates the alert was closed due to policy change
	ClosureReasonAmendment = "amendment"

	// ClosureReasonPrivatePackage indicates the alert was closed because the package was determined to be private and not a compliance issue
	ClosureReasonPrivatePackage = "private_package"

	// ClosureReasonInaccurateLicense indicates the alert was closed because the initially detected license was determined to be inaccurate
	ClosureReasonInaccurateLicense = "inaccurate_license"

	// ClosureReasonPolicyEdited is a system-initiated closure reflecting a policy change based on either another alert or just directly in the policy UI
	ClosureReasonPolicyEdited = "policy_edited"

	// ClosureReasonFixed is a system-initiated closure reflecting that the underlying dependency was removed
	ClosureReasonFixed = "fixed"
)

// ClosureReasonFromProto converts a proto ClosureReason enum to a nullable DB string.
func ClosureReasonFromProto(reason proto.ClosureReason) *string {
	var s string
	switch reason {
	case proto.ClosureReason_CLOSURE_REASON_AMENDMENT:
		s = ClosureReasonAmendment
	case proto.ClosureReason_CLOSURE_REASON_PRIVATE_PACKAGE:
		s = ClosureReasonPrivatePackage
	case proto.ClosureReason_CLOSURE_REASON_INACCURATE_LICENSE:
		s = ClosureReasonInaccurateLicense
	case proto.ClosureReason_CLOSURE_REASON_POLICY_EDITED:
		s = ClosureReasonPolicyEdited
	case proto.ClosureReason_CLOSURE_REASON_FIXED:
		s = ClosureReasonFixed
	default:
		return nil
	}
	return &s
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
