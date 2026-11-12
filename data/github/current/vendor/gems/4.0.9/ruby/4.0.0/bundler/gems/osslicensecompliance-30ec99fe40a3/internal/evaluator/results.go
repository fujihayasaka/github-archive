package evaluator

import (
	"github.com/github/osslicensecompliance/internal/models"
	"github.com/github/osslicensecompliance/pkg/proto/v0"
)

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

// PackageFailure provides details about why a package is not allowed.
type PackageFailure struct {
	Package models.Package
	Reason  FailureReason
	Level   proto.PolicyLevel
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
