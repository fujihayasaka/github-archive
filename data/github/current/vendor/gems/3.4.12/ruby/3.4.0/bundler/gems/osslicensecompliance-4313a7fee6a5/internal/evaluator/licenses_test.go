package evaluator

import (
	"testing"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/osslicensecompliance/internal/models"
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

	res := staticLicensePatch(models.PMgomod, "golang.org/x/net/v0.0.0-20210503060351-7fd8e65b6420", "BSD-3-Clause AND OTHER", log.NewNullLogger())
	r.Equal("BSD-3-Clause AND LicenseRef-github-google-patent-license-golang", res)
}

func TestPatchGolangXNoMatch(t *testing.T) {
	r := require.New(t)

	res := staticLicensePatch(models.PMgomod, "golang.org/x/net/v0.0.0-20210503060351-7fd8e65b6420", "BSD-2-Clause AND OTHER", log.NewNullLogger())
	r.Equal("BSD-2-Clause AND OTHER", res)
}

func TestPatchGolangPackage(t *testing.T) {
	r := require.New(t)

	res := staticLicensePatch(models.PMgomod, "github.com/itongsys/parquet-go/v1.6.1", "BSD-3-Clause", log.NewNullLogger())
	r.Equal("BSD-3-Clause", res)
}
