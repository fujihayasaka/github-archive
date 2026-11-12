package evaluator

import (
	"testing"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/osslicensecompliance/pkg/proto/v0"
	"github.com/stretchr/testify/require"
)

func TestInvalidSpdxReplacement(t *testing.T) {
	var testCases = []struct {
		name     string
		value    string
		expected string
	}{
		{
			name:     "simple other",
			value:    "OTHER",
			expected: otherReplacement,
		},
		{
			name:     "simple noassertion",
			value:    "NOASSERTION",
			expected: noAssertionReplacement,
		},
		{
			name:     "both",
			value:    `GPL-2.0-only AND OTHER AND NOASSERTION AND MIT`,
			expected: `GPL-2.0-only AND ` + otherReplacement + ` AND ` + noAssertionReplacement + ` AND MIT`,
		},
	}
	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			result := replaceInvalidSpdxValues(tc.value)
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

func TestNormalizeSpdxID(t *testing.T) {
	testCases := []struct {
		name     string
		input    string
		expected string
	}{
		{
			name:     "simple lowercase license",
			input:    "mit",
			expected: "MIT",
		},
		{
			name:     "simple uppercase license",
			input:    "MIT",
			expected: "MIT",
		},
		{
			name:     "mixed case license",
			input:    "MiT",
			expected: "MIT",
		},
		{
			name:     "apache with version",
			input:    "apache-2.0",
			expected: "Apache-2.0",
		},
		{
			name:     "apache mixed case",
			input:    "APACHE-2.0",
			expected: "Apache-2.0",
		},
		{
			name:     "BSD with clause number",
			input:    "bsd-3-clause",
			expected: "BSD-3-Clause",
		},
		{
			name:     "GPL with version",
			input:    "gpl-3.0-only",
			expected: "GPL-3.0-only",
		},
		{
			name:     "simple OR expression",
			input:    "mit OR apache-2.0",
			expected: "MIT OR Apache-2.0",
		},
		{
			name:     "simple AND expression",
			input:    "bsd-3-clause AND gpl-3.0-only",
			expected: "BSD-3-Clause AND GPL-3.0-only",
		},
		{
			name:     "expression with WITH exception",
			input:    "apache-2.0 WITH llvm-exception",
			expected: "Apache-2.0 WITH LLVM-exception",
		},
		{
			name:     "complex nested expression",
			input:    "(mit OR apache-2.0) AND bsd-2-clause",
			expected: "(MIT OR Apache-2.0) AND BSD-2-Clause",
		},
		{
			name:     "expression with multiple operators",
			input:    "mit OR apache-2.0 OR gpl-3.0-only",
			expected: "MIT OR Apache-2.0 OR GPL-3.0-only",
		},
		{
			name:     "deeply nested expression",
			input:    "((bsd-2-clause AND gpl-3.0-only) OR mit) AND apache-2.0",
			expected: "((BSD-2-Clause AND GPL-3.0-only) OR MIT) AND Apache-2.0",
		},
		{
			name:     "LicenseRef preserves case",
			input:    "LicenseRef-My-Custom-License",
			expected: "LicenseRef-My-Custom-License",
		},
		{
			name:     "LicenseRef with mixed case prefix normalized",
			input:    "licenseref-My-Custom-License",
			expected: "LicenseRef-My-Custom-License",
		},
		{
			name:     "LicenseRef with lowercase prefix normalized",
			input:    "licenseref-custom",
			expected: "LicenseRef-custom",
		},
		{
			name:     "LicenseRef with UPPERCASE prefix normalized",
			input:    "LICENSEREF-CUSTOM",
			expected: "LicenseRef-CUSTOM",
		},
		{
			name:     "expression with LicenseRef",
			input:    "mit OR LicenseRef-Custom",
			expected: "MIT OR LicenseRef-Custom",
		},
		{
			name:     "expression with lowercase licenseref normalized",
			input:    "mit OR licenseref-custom",
			expected: "MIT OR LicenseRef-custom",
		},
		{
			name:     "expression with mixed case LicenseRef prefix normalized",
			input:    "apache-2.0 OR LiCeNsErEf-My-Custom",
			expected: "Apache-2.0 OR LicenseRef-My-Custom",
		},
		{
			name:     "already canonical case",
			input:    "MIT",
			expected: "MIT",
		},
		{
			name:     "empty string",
			input:    "",
			expected: "",
		},
		{
			name:     "whitespace variations preserved",
			input:    "mit  OR  apache-2.0",
			expected: "MIT  OR  Apache-2.0",
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			result := NormalizeSpdxID(tc.input)
			require.Equal(t, tc.expected, result, "NormalizeSpdxID(%q) should return %q but got %q", tc.input, tc.expected, result)
		})
	}
}
