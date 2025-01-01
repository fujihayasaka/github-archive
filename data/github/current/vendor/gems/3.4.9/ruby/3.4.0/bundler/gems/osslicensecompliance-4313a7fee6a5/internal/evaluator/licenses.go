package evaluator

import (
	"fmt"
	"regexp"
	"strings"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/osslicensecompliance/internal/models"
)

var otherReplacer = regexp.MustCompile(`\bOTHER\b`)

const otherReplacement = "LicenseRef-clearlydefined-OTHER"

var noAssertionReplacer = regexp.MustCompile(`\bNOASSERTION\b`)

const noAssertionReplacement = "LicenseRef-clearlydefined-NOASSERTION"

// replaceInvalidSpdxValues replaces the values "OTHER" and "NOASSERTION"
// because they are not valid SPDX license identifiers. It replaces them
// with LicenseRefs, which are valid SPDX license identifiers.
func replaceInvalidSpdxValues(value string) string {
	value = otherReplacer.ReplaceAllString(value, otherReplacement)
	value = noAssertionReplacer.ReplaceAllString(value, noAssertionReplacement)
	return value
}

type licenseOverride struct {
	namePrefix      string
	expectedLicense string
	newLicense      string
}

// licenseOverrides is a map of dependency coordinates (via regex) to the _additional_
// license they should be attributed with
var licenseOverrides = map[models.PackageManager][]licenseOverride{
	models.PMgomod: {
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
func staticLicensePatch(pm models.PackageManager, packageName, license string, logger log.Logger) string {
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
