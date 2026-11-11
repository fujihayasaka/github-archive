package evaluator

import (
	"fmt"
	"regexp"
	"strings"
	"sync"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-spdx/v2/spdxexp"
	"github.com/github/go-spdx/v2/spdxexp/spdxlicenses"
	"github.com/github/osslicensecompliance/pkg/proto/v0"
)

// handleEmptyLicense replaces empty license strings with LicenseRefEmpty.
// DG-API now handles transforming OTHER/NOASSERTION to LicenseRef-github-* format,
// so we only need to handle empty strings here.
func handleEmptyLicense(value string) string {
	if value == "" {
		return LicenseRefEmpty
	}
	return value
}

type licenseOverride struct {
	namePrefix      string
	expectedLicense string
	newLicense      string
}

// licenseOverrides is a map of dependency coordinates (via regex) to the _additional_
// license they should be attributed with
var licenseOverrides = map[proto.PackageManager][]licenseOverride{
	proto.PackageManager_PACKAGE_MANAGER_GOMOD: {
		{
			namePrefix:      "golang.org/x/",
			expectedLicense: "BSD-3-Clause AND OTHER",
			newLicense:      "BSD-3-Clause AND LicenseRef-github-google-patent-license-golang",
		},
		{
			namePrefix:      "google.golang.org/protobuf",
			expectedLicense: "BSD-3-Clause AND OTHER",
			newLicense:      "BSD-3-Clause AND LicenseRef-github-google-patent-license-golang",
		},
	},
}

// staticLicensePatch takes in a dependency and returns a patched license string based on
// the licenseOverrides map
func staticLicensePatch(pm proto.PackageManager, packageName, license string, logger log.Logger) string {
	overrides, ok := licenseOverrides[pm]
	if !ok {
		return license
	}
	for _, override := range overrides {
		if strings.HasPrefix(packageName, override.namePrefix) && license == override.expectedLicense {
			logger.Debug(fmt.Sprintf("Patching license for %v", packageName))
			return override.newLicense
		}
	}
	return license
}

var (
	canonicalLicenseMap     map[string]string
	canonicalLicenseMapOnce sync.Once
)

// buildCanonicalLicenseMap creates a lowercase-to-canonical mapping of all SPDX licenses and exceptions
func buildCanonicalLicenseMap() map[string]string {
	canonicalLicenseMapOnce.Do(func() {
		canonicalLicenseMap = make(map[string]string)

		// Add all licenses
		for _, license := range spdxlicenses.GetLicenses() {
			canonicalLicenseMap[strings.ToLower(license)] = license
		}

		// Add all exceptions
		for _, exception := range spdxlicenses.GetExceptions() {
			canonicalLicenseMap[strings.ToLower(exception)] = exception
		}
	})
	return canonicalLicenseMap
}

// NormalizeSpdxID normalizes an SPDX license expression to use canonical case for
// standard SPDX identifiers. For LicenseRef identifiers, it normalizes the "LicenseRef-"
// prefix to canonical case while preserving the case of the custom identifier portion.
// For example, "mit OR apache-2.0" becomes "MIT OR Apache-2.0", and
// "licenseref-custom" becomes "LicenseRef-custom".
func NormalizeSpdxID(spdxID string) string {
	if spdxID == "" {
		return ""
	}

	// First, normalize LicenseRef prefix to canonical "LicenseRef-" form
	// The SPDX spec requires "LicenseRef-" but users might type it with different casing
	// Do this first so extraction can work properly if the input has non-canonical LicenseRef
	result := spdxID
	licenseRefPattern := regexp.MustCompile(`(?i)\bLicenseRef-`)
	result = licenseRefPattern.ReplaceAllStringFunc(result, func(match string) string {
		// Replace with canonical "LicenseRef-" while preserving the rest
		return "LicenseRef-"
	})

	// Extract all licenses from the expression (handles operators, parentheses, etc.)
	// Note: ExtractLicenses returns canonical case for standard licenses and exceptions,
	// including WITH clauses (e.g., "Apache-2.0 WITH LLVM-exception").
	// However, we still perform additional normalization below to handle any non-canonical
	// forms that may remain due to user input or edge cases, ensuring robustness.
	// We must still normalize `LicenseRef-` entries ourselves, so those are special-cased.
	extracted, err := spdxexp.ExtractLicenses(result)
	if err != nil {
		// If extraction fails, still return with LicenseRef normalized
		return result
	}

	// Build canonical map (cached after first call)
	canonicalMap := buildCanonicalLicenseMap()

	// Normalize standard licenses by replacing each with its canonical form
	for _, license := range extracted {
		// Skip LicenseRef entries - they've already been normalized
		if strings.HasPrefix(license, "LicenseRef-") {
			continue
		}

		// For licenses WITH exceptions, ExtractLicenses returns them in canonical form
		// We need to handle the whole "license WITH exception" phrase
		if strings.Contains(license, " WITH ") {
			// Use case-insensitive regex to replace the entire expression
			// Need to escape special regex characters in the license string
			escapedLicense := regexp.QuoteMeta(license)
			// Make it case-insensitive and use word boundaries
			pattern := regexp.MustCompile(`(?i)\b` + escapedLicense + `\b`)
			result = pattern.ReplaceAllString(result, license)
		} else {
			// Look up canonical form (case-insensitive)
			if canonical, ok := canonicalMap[strings.ToLower(license)]; ok {
				// Use case-insensitive regex with word boundaries to replace
				// This ensures we don't replace partial matches
				pattern := regexp.MustCompile(`(?i)\b` + regexp.QuoteMeta(license) + `\b`)
				result = pattern.ReplaceAllString(result, canonical)
			}
		}
	}

	return result
}
