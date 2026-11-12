// Package evaluator provides functions to evaluate packages against the
// applicable license policy.
package evaluator

import (
	"fmt"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-spdx/v2/spdxexp"
	"github.com/github/osslicensecompliance/internal/models"
	"github.com/github/osslicensecompliance/pkg/proto/v0"
)

// PolicyResultsForRepository evaluates the dependencies for a whole repository
// and returns the results of the evaluation.
// The only error possible while evaluating policies for packages is an problem
// with parsing the license expressions. Policy license expressions should
// ideally be validated in advance, so errors that show up here are more likely
// unexpected strings in the license field of a package. These don't fail the
// whole result, but are instead returned as a count.
func PolicyResultsForRepository(dependencies map[string]models.Package, policy *models.CompletePolicy, distributionContext string, logger log.Logger) RepositoryResults {
	logger = logger.Named("evaluator")
	successCount := 0
	failureCount := 0
	errorCount := 0
	var lastError error
	failures := []PackageFailure{}
	for _, packageInfo := range dependencies {
		result, err := PolicyResultForPackage(packageInfo, policy, distributionContext, logger)
		if err != nil {
			errorCount++
			lastError = err
			continue
		}
		if result == nil {
			successCount++
			continue
		}
		failures = append(failures, *result)
		failureCount++
	}
	return RepositoryResults{
		SuccessCount: successCount,
		FailureCount: failureCount,
		ErrorCount:   errorCount,
		LastError:    lastError,
		Failures:     failures,
	}
}

// LicenseRefEmpty is a license ref created by GitHub for packages that are
// missing a license entirely (empty string). This generally indicates that
// ClearlyDefined has not processed the package.
//
// TODO: We should replace this mechanism with an explicit policy flag:
// https://github.com/github/artifact-lifecycle/issues/271
const LicenseRefEmpty = "LicenseRef-github-EMPTY"

// PolicyResultForPackage evaluates whether the provided package is allowed based on
// the policy given.
// If the package is allowed, it returns nil. Otherwise, it returns a
// PackageFailure with details about why the package is not allowed.
func PolicyResultForPackage(packageInfo models.Package, policy *models.CompletePolicy, distributionContext string, logger log.Logger) (*PackageFailure, error) {
	logger = logger.WithFields(kvp.String("dependency", models.PackageManagerToString(packageInfo.PackageManager)+packageInfo.Name))
	allowed, extraAllowedSpdxIDs, failureResult := evaluatePackageAllowed(packageInfo, policy, distributionContext, logger)
	if allowed && extraAllowedSpdxIDs == nil {
		return nil, nil
	}
	if failureResult != nil {
		return failureResult, nil
	}

	allowList := policy.GetAllowList(distributionContext)
	if len(allowList) == 0 {
		logger.Debug("There are no licenses compatible with this set of distribution contexts")
		return &PackageFailure{
			Package: packageInfo,
			Reason:  LicenseNotAllowed,
			Level:   proto.PolicyLevel_POLICY_LEVEL_REPOSITORY,
		}, nil
	}
	license := packageInfo.License
	license = staticLicensePatch(packageInfo.PackageManager, packageInfo.Name, license, logger)
	license = replaceInvalidSpdxValues(license)
	if extraAllowedSpdxIDs != nil {
		allowList = append(allowList, extraAllowedSpdxIDs...)
	}
	logger.Debug(fmt.Sprintf("Evaluating license %s against allow list (%d)", license, len(allowList)))
	allowed, err := spdxexp.Satisfies(license, allowList)
	if err != nil {
		logger.WithError(err).Error("Error evaluating license")
		return nil, err
	}
	if !allowed {
		logger.Debug("License not allowed")
		return &PackageFailure{
			Reason:  LicenseNotAllowed,
			Package: packageInfo,
		}, nil
	}
	logger.Debug("License allowed")
	return nil, nil
}

// evaluatePackageAllowed evaluates whether the provided package is allowed based
// on the layers of the policy.
// It returns (true, extraAllowedSpdxIDs, nil) if a package is allowed, where extraAllowedSpdxIDs is an optional
// list of licenses that should match.
// It returns (false, nil, nil) if there's no explicit result.
// (false, nil, PackageFailure) if the package is not allowed.
func evaluatePackageAllowed(packageInfo models.Package, policy *models.CompletePolicy, distributionContext string, logger log.Logger) (bool, []string, *PackageFailure) {
	packagePolicy, level := policy.GetPackagePolicy(packageInfo.PackageManager, packageInfo.Name, distributionContext)
	if packagePolicy == nil {
		return false, nil, nil
	}

	allowed, extraAllowedSpdxIDs, failure := packageAllowedByPolicy(packageInfo, packagePolicy, level, logger)
	if allowed || failure != nil {
		return allowed, extraAllowedSpdxIDs, failure
	}

	return false, nil, nil
}

// packageAllowedByPolicy evaluates the package policy at a single level. This
// is already package-specific by the time it gets here.
// It returns true if the package is allowed, but with a possible optional
// list of licenses that are allowed for the package.
// It returns `false, nil, nil` if there's no explicit result (eg no policy)
// It returns `false, nil, PackageFailure` if the package is not allowed.
// Note that blocked packages are blocked regardless of the ExtraAllowedSpdxIds list.
func packageAllowedByPolicy(packageInfo models.Package, packagePolicy *proto.PackagePolicy, level proto.PolicyLevel, logger log.Logger) (bool, []string, *PackageFailure) {
	if packagePolicy == nil {
		logger.Debug(fmt.Sprintf("No policy found at level: %d", level))
		return false, nil, nil
	}
	switch packagePolicy.Action {
	case proto.PackageAction_PACKAGE_ACTION_BLOCKED:
		logger.Debug(fmt.Sprintf("Package blocked at level: %d", level))
		return false, nil, &PackageFailure{
			Package: packageInfo,
			Reason:  PackageBlocked,
			Level:   level,
		}
	case proto.PackageAction_PACKAGE_ACTION_ALLOWED:
		logger.Debug(fmt.Sprintf("Package allowed at level: %d", level))
		return true, packagePolicy.ExtraAllowedSpdxIds, nil
	case proto.PackageAction_PACKAGE_ACTION_PRIVATE:
		logger.Debug(fmt.Sprintf("Package private at level: %d", level))
		return true, nil, nil
	}
	logger.Debug(fmt.Sprintf("No action found at level: %d", level))
	return false, nil, nil
}

// AlertSatisfiesPolicy evaluates whether the given alert satisfies the provided policy
func AlertSatisfiesPolicy(alert *models.Alert, policy *models.CompletePolicy, distributionContext string) (bool, error) {
	pkg := models.Package{
		PackageManager: alert.PackageEcosystem,
		Name:           alert.PackageName,
	}

	allowed, extraAllowedSpdxIDs, _ := evaluatePackageAllowed(pkg, policy, distributionContext, log.Named("evaluator"))
	if allowed && extraAllowedSpdxIDs == nil {
		return true, nil
	}

	allowList := policy.GetAllowList(distributionContext)
	if extraAllowedSpdxIDs != nil {
		allowList = append(allowList, extraAllowedSpdxIDs...)
	}

	if len(allowList) == 0 {
		return false, nil
	}

	license := replaceInvalidSpdxValues(alert.SPDXLicenseExpression)
	return spdxexp.Satisfies(license, allowList)
}
