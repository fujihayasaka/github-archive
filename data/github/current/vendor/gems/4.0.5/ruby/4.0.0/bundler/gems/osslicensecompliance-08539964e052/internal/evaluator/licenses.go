package evaluator

import (
	"fmt"
	"strings"

	"github.com/github/github-telemetry-go/log"
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
