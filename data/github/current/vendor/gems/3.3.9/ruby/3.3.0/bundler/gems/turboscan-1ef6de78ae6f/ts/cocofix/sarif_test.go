package cocofix

import (
	"regexp"
	"testing"

	"github.com/github/turboscan/ts"
	"github.com/stretchr/testify/require"
)

func TestSarifBuilder(t *testing.T) {
	opts := SarifBuilderOpts{AllowNonDefaultRules: false}
	b, err := NewSarifBuilder(opts)
	require.NoError(t, err)
	b.AppendRun(&ToolInfo{
		ToolName:    "CodeQL",
		ToolVersion: "2.16.2",
	}).AppendResult(&Result{
		Number:          1,
		GUID:            "guid",
		SarifIdentifier: "js/reflected-xss",
		Message:         "Cross-site scripting vulnerability due to a user-provided value.",
		MessageMarkdown: "Cross-site scripting vulnerability due to a [user-provided value](1).",
		FilePath:        "index.js",
		Region: ts.Region{
			StartLine:   4,
			StartColumn: 37,
			EndColumn:   64,
		},
	})

	require.Len(t, b.sarif.Runs[0].Results, 1)
	require.Equal(t, "js/reflected-xss", b.sarif.Runs[0].Results[0].RuleId)
	require.Equal(t, "js/reflected-xss", b.sarif.Runs[0].Tool.Driver.Rules[0].Id)
	require.Equal(t, "Reflected cross-site scripting", b.sarif.Runs[0].Tool.Driver.Rules[0].ShortDescription.Text)

	byt, err := b.BuildIndented()
	require.NoError(t, err)
	require.NotEmpty(t, byt)

	content := readTestFile(t, "reflected-xss.sarif")
	// The queryURI for the test query depends on the specific version of the rule that
	// is loaded, and it includes a SHA of the release. This is the only part of the SARIF that is
	// dependent on the version of the rule, so we normalize it to a known value.
	regex := regexp.MustCompile(`https://github.com/github/codeql/blob/([a-fA-F0-9]+)/javascript/ql/src/Security/CWE-079/ReflectedXss.ql`)
	byt = regex.ReplaceAll(byt, []byte("https://github.com/github/codeql/blob/753d78a695a3290dbadc725fe1bd0ee759f37734/javascript/ql/src/Security/CWE-079/ReflectedXss.ql"))
	require.Equal(t, string(content), string(byt))

	rb := &RunBuilder{
		run: b.sarif.Runs[0],
		sb:  b,
	}
	rb.AppendResult(&Result{
		Number:          2,
		GUID:            "guid",
		SarifIdentifier: "js/reflected-xss",
		Message:         "m2",
		MessageMarkdown: "md",
		FilePath:        "file2.ts",
	})
	require.Len(t, b.sarif.Runs[0].Results, 2)
	require.Len(t, b.sarif.Runs[0].Tool.Driver.Rules, 1)

	// Now append a new rule
	rb.AppendResult(&Result{
		Number:          3,
		GUID:            "guid",
		SarifIdentifier: "js/multiple-arguments-to-set-constructor",
		Message:         "m2",
		MessageMarkdown: "md",
		FilePath:        "file2.ts",
	})
	require.Len(t, b.sarif.Runs[0].Results, 3)
	require.Equal(t, b.sarif.Runs[0].Results[0].RuleIndex, 0)
	require.Len(t, b.sarif.Runs[0].Tool.Driver.Rules, 2)
	require.Equal(t, b.sarif.Runs[0].Results[2].RuleIndex, 1)
}

func TestSarifBuilderWhenRuleNotFound(t *testing.T) {
	opts := SarifBuilderOpts{AllowNonDefaultRules: false}
	b, err := NewSarifBuilder(opts)
	require.NoError(t, err)
	b.AppendRun(&ToolInfo{
		ToolName:    "CodeQL",
		ToolVersion: "2.16.2",
	}).AppendResult(&Result{
		Number:          1,
		GUID:            "guid",
		SarifIdentifier: "joo/bar",
		Message:         "message",
		MessageMarkdown: "md",
		FilePath:        "file.ts",
		Rule: &ts.Rule{
			SarifIdentifier:  "joo/bar",
			Name:             "joo/bar",
			ShortDescription: "short",
			FullDescription:  "full",
			Help:             "help",
		},
	})
	require.NotEmpty(t, b.sarif.Runs[0].Results)
	require.NotEmpty(t, b.sarif.Runs[0].Tool.Driver.Rules)
	require.Equal(t, "joo/bar", b.sarif.Runs[0].Tool.Driver.Rules[0].Id)
	require.Nil(t, b.sarif.Runs[0].Tool.Driver.Rules[0].ShortDescription)
}

func TestSarifBuilderWhenRuleNotFoundAndAllowNonDefaultRules(t *testing.T) {
	opts := SarifBuilderOpts{AllowNonDefaultRules: true}
	b, err := NewSarifBuilder(opts)
	require.NoError(t, err)
	b.AppendRun(&ToolInfo{
		ToolName:    "CodeQL",
		ToolVersion: "2.16.2",
	}).AppendResult(&Result{
		Number:          1,
		GUID:            "guid",
		SarifIdentifier: "joo/bar",
		Message:         "message",
		MessageMarkdown: "md",
		FilePath:        "file.ts",
		Rule: &ts.Rule{
			SarifIdentifier:  "joo/bar",
			Name:             "joo/bar",
			ShortDescription: "short",
			FullDescription:  "full",
			Help:             "help",
		},
	})
	require.NotEmpty(t, b.sarif.Runs[0].Results)
	require.NotEmpty(t, b.sarif.Runs[0].Tool.Driver.Rules)
	require.Equal(t, "joo/bar", b.sarif.Runs[0].Tool.Driver.Rules[0].Id)
	require.Equal(t, "short", b.sarif.Runs[0].Tool.Driver.Rules[0].ShortDescription.Text)
	require.Equal(t, "help", b.sarif.Runs[0].Tool.Driver.Rules[0].Help.Markdown)
}
