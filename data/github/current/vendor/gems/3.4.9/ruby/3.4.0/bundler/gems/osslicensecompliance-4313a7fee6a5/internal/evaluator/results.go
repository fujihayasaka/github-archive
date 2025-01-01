package evaluator

import "github.com/github/osslicensecompliance/internal/models"

// FailureReason is a reason why a package is not allowed.
type FailureReason int

const (
	// LicenseNotAllowed means that the package's license expression cannot
	// be satisfied by the policy's allow list.
	LicenseNotAllowed FailureReason = iota
	// PackageBlocked means that the package is explicitly blocked by the
	// policy.
	PackageBlocked
	// Expired means that the license allowance has expired.
	Expired
)

// FailureLevel denotes whether the failure was at the repository,
// organization, or enterprise level.
type FailureLevel int

const (
	// NoLevel means that the failure was not at any level. This will be
	// the case for LicenseNotAllowed because we don't have a way to
	// attribute that failure to a level.
	NoLevel FailureLevel = iota
	// RepositoryLevel means that the failure was at the repository level.
	RepositoryLevel
	// OrganizationLevel means that the failure was at the organization level.
	OrganizationLevel
	// EnterpriseLevel means that the failure was at the enterprise level.
	EnterpriseLevel
)

// PackageFailure provides details about why a package is not allowed.
type PackageFailure struct {
	Package models.Package
	Reason  FailureReason
	Level   FailureLevel
}

// RepositoryResults provides the results of evaluating a repository's
// dependencies.
type RepositoryResults struct {
	SuccessCount int
	FailureCount int
	ErrorCount   int
	LastError    error
	Failures     []PackageFailure
}
