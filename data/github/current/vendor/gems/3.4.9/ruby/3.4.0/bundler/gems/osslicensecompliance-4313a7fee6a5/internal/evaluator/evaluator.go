// Package evaluator provides functions to evaluate packages against the
// applicable license policy.
package evaluator

import (
	"fmt"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-spdx/v2/spdxexp"
	"github.com/github/osslicensecompliance/internal/models"
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
	logger = logger.WithFields(kvp.String("dependency", packageInfo.PackageManager.String()+":"+packageInfo.Name))
	allowed, packageMatchLicenses, failureResult := evaluatePackageAllowed(packageInfo, policy, distributionContext, logger)
	if allowed && packageMatchLicenses == nil {
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
			Level:   RepositoryLevel,
		}, nil
	}
	license := packageInfo.License
	if license == "" {
		license = LicenseRefEmpty
	}
	license = staticLicensePatch(packageInfo.PackageManager, packageInfo.Name, license, logger)
	license = replaceInvalidSpdxValues(license)
	if packageMatchLicenses != nil {
		allowList = append(allowList, packageMatchLicenses...)
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
// It returns (true, matchLicenses, nil) if a package is allowed, where matchLicenses is an optional
// list of licenses that should match.
// It returns (false, nil, nil) if there's no explicit result.
// (false, nil, PackageFailure) if the package is not allowed.
func evaluatePackageAllowed(packageInfo models.Package, policy *models.CompletePolicy, distributionContext string, logger log.Logger) (bool, []string, *PackageFailure) {
	if policy.RepositoryPolicy != nil {
		repoPolicy := policy.RepositoryPolicy.Policy.GetPackagePolicy(packageInfo.PackageManager, packageInfo.Name, distributionContext)
		allowed, matchLicenses, failure := packageAllowedByPolicy(packageInfo, repoPolicy, RepositoryLevel, logger)
		if allowed || failure != nil {
			return allowed, matchLicenses, failure
		}
	}

	if policy.OrganizationPolicy != nil {
		orgPolicy := policy.OrganizationPolicy.Policy.GetPackagePolicy(packageInfo.PackageManager, packageInfo.Name, distributionContext)
		allowed, matchLicenses, failure := packageAllowedByPolicy(packageInfo, orgPolicy, OrganizationLevel, logger)
		if allowed || failure != nil {
			return allowed, matchLicenses, failure
		}
	}

	if policy.EnterprisePolicy != nil {
		enterprisePolicy := policy.EnterprisePolicy.Policy.GetPackagePolicy(packageInfo.PackageManager, packageInfo.Name, distributionContext)
		allowed, matchLicenses, failure := packageAllowedByPolicy(packageInfo, enterprisePolicy, EnterpriseLevel, logger)
		if allowed || failure != nil {
			return allowed, matchLicenses, failure
		}
	}
	return false, nil, nil
}

// packageAllowedByPolicy evaluates the package policy at a single level. This
// is already package-specific by the time it gets here.
// It returns true if the package is allowed, but with a possible optional
// list of licenses that are allowed for the package.
// It returns `false, nil, nil` if there's no explicit result (eg no policy)
// It returns `false, nil, PackageFailure` if the package is not allowed.
// Note that blocked packages are blocked regardless of the MatchLicenses list.
func packageAllowedByPolicy(packageInfo models.Package, packagePolicy *models.PackagePolicy, level FailureLevel, logger log.Logger) (bool, []string, *PackageFailure) {
	if packagePolicy == nil {
		logger.Debug(fmt.Sprintf("No policy found at level: %d", level))
		return false, nil, nil
	}
	switch packagePolicy.Action {
	case models.PackageActionBlock:
		logger.Debug(fmt.Sprintf("Package blocked at level: %d", level))
		return false, nil, &PackageFailure{
			Package: packageInfo,
			Reason:  PackageBlocked,
			Level:   level,
		}
	case models.PackageActionAllow:
		logger.Debug(fmt.Sprintf("Package allowed at level: %d", level))
		return true, packagePolicy.MatchLicenses, nil
	case models.PackageActionPrivate:
		logger.Debug(fmt.Sprintf("Package private at level: %d", level))
		return true, nil, nil
	}
	logger.Debug(fmt.Sprintf("No action found at level: %d", level))
	return false, nil, nil
}
