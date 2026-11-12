package evaluator

import (
	"testing"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/osslicensecompliance/pkg/proto/v0"
	"github.com/stretchr/testify/require"
)

func TestHandleEmptyLicense(t *testing.T) {
	var testCases = []struct {
		name     string
		value    string
		expected string
	}{
		{
			name:     "empty string returns LicenseRefEmpty",
			value:    "",
			expected: LicenseRefEmpty,
		},
		{
			name:     "non-empty string unchanged",
			value:    "MIT",
			expected: "MIT",
		},
		{
			name:     "LicenseRef-github-NOASSERTION unchanged (DG-API handles this now)",
			value:    "LicenseRef-github-NOASSERTION",
			expected: "LicenseRef-github-NOASSERTION",
		},
		{
			name:     "LicenseRef-github-OTHER unchanged (DG-API handles this now)",
			value:    "LicenseRef-github-OTHER",
			expected: "LicenseRef-github-OTHER",
		},
	}
	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			result := handleEmptyLicense(tc.value)
			require.Equal(t, tc.expected, result)
		})
	}
}

func TestPatchGolangX(t *testing.T) {
	r := require.New(t)

	res := staticLicensePatch(proto.PackageManager_PACKAGE_MANAGER_GOMOD, "golang.org/x/net/v0.0.0-20210503060351-7fd8e65b6420", "BSD-3-Clause AND OTHER", log.NewNullLogger())
	r.Equal("BSD-3-Clause AND LicenseRef-github-google-patent-license-golang", res)
}

func TestPatchGolangXNoMatch(t *testing.T) {
	r := require.New(t)

	res := staticLicensePatch(proto.PackageManager_PACKAGE_MANAGER_GOMOD, "golang.org/x/net/v0.0.0-20210503060351-7fd8e65b6420", "BSD-2-Clause AND OTHER", log.NewNullLogger())
	r.Equal("BSD-2-Clause AND OTHER", res)
}

func TestPatchGolangPackage(t *testing.T) {
	r := require.New(t)

	res := staticLicensePatch(proto.PackageManager_PACKAGE_MANAGER_GOMOD, "github.com/itongsys/parquet-go/v1.6.1", "BSD-3-Clause", log.NewNullLogger())
	r.Equal("BSD-3-Clause", res)
}
