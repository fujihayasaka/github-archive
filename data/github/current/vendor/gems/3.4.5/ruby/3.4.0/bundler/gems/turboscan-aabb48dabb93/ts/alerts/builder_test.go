package alerts

import (
	"context"
	"strings"
	"testing"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/limits"
	"github.com/github/turboscan/ts/proto"
	"github.com/github/turboscan/ts/sarif/samples"
	v210turboscan "github.com/github/turboscan/ts/sarif/v2_1_0_turboscan"
	"github.com/stretchr/testify/require"
)

const (
	testRepoID     = ts.RepositoryEID(1234)
	testAnalysisID = 1
)

func defaultBuilder() *Builder {
	lt := limits.LimitsDefault()
	return NewAlertsBuilder(&ts.Analysis{RepositoryID: testRepoID, ID: testAnalysisID, Rules: defaultRules()}, &lt)
}

func TestBuild(t *testing.T) {
	sarif := samples.RequireSARIF(t, "testdata/example.sarif")
	run := sarif.Runs[0]
	require.Len(t, run.Results, 2)

	builder := defaultBuilder()
	alerts, err := builder.Build(context.Background(), run, "")
	require.NoError(t, err)

	require.Len(t, alerts, 2)
	require.EqualValues(t, testRepoID, alerts[0].RepositoryID)
	require.EqualValues(t, testRepoID, alerts[1].RepositoryID)

	require.Nil(t, alerts[0].CodeFlowsDocument)
	require.Nil(t, alerts[1].CodeFlowsDocument)

	require.Len(t, alerts[0].RelatedLocations, 0)
	require.Len(t, alerts[1].RelatedLocations, 2)

	require.Equal(t, "here", alerts[1].RelatedLocations[0].Message)

	require.EqualValues(t, 7, alerts[0].Region.StartColumn)                      // Set explicitly.
	require.EqualValues(t, 1, alerts[1].Region.StartColumn)                      // Unspecified so should default to 1.
	require.EqualValues(t, 33, alerts[1].RelatedLocations[0].Region.StartColumn) // Set explicitly.
	require.EqualValues(t, 1, alerts[1].RelatedLocations[1].Region.StartColumn)  // Unspecified so should default to 1.
}

func TestBuild_MissingMessage(t *testing.T) {
	sarif := samples.RequireSARIF(t, "testdata/example.sarif")
	run := sarif.Runs[0]
	run.Results[1].Message = nil

	builder := defaultBuilder()
	alerts, err := builder.Build(context.Background(), run, "")
	require.NotNil(t, err)
	require.ElementsMatch(t, []error{ErrResultExpected}, SplitErrors(err))
	require.Len(t, alerts, 1)
}

func TestBuild_LongMessages(t *testing.T) {
	sarif := samples.RequireSARIF(t, "testdata/example.sarif")
	run := sarif.Runs[0]
	run.Results[0].Message.Text = strings.Repeat("x", 10*1024)

	builder := defaultBuilder()
	alerts, err := builder.Build(context.Background(), run, "")
	require.Nil(t, err)
	require.Len(t, alerts, 2)

	// We should not assume that the order is preserved.
	if alerts[0].RuleSarifIdentifier == sarif.Runs[0].Results[0].RuleId {
		require.Equal(t, len(alerts[0].Message), 4096)
		require.Equal(t, len(alerts[1].Message), len(sarif.Runs[0].Results[1].Message.Text))
	} else {
		require.Equal(t, len(alerts[1].Message), 4096)
		require.Equal(t, len(alerts[0].Message), len(sarif.Runs[0].Results[0].Message.Text))
	}

}

func TestBuildNoResults(t *testing.T) {
	sarif := samples.RequireSARIF(t, "testdata/no-results.sarif")
	run := sarif.Runs[0]
	require.Nil(t, run.Results)

	builder := defaultBuilder()
	alerts, err := builder.Build(context.Background(), run, "")
	require.NoError(t, err)
	require.Len(t, alerts, 0)
}

func TestCodeFlows(t *testing.T) {
	builder := defaultBuilder()
	sarif := samples.RequireSARIF(t, "../sarif/testdata/example2.sarif")
	run := sarif.Runs[0]
	alerts, err := builder.Build(context.Background(), run, "")
	require.Nil(t, err)

	require.Equal(t, "components/camel-http-common/src/main/java/org/apache/camel/http/common/DefaultHttpBinding.java", alerts[0].FilePath)
	require.Len(t, alerts[0].CodeFlowsDocument.Document, 191)
	require.EqualValues(t, 20, alerts[0].CodeFlowsDocument.Document[0].Region.StartColumn) // Set explicitly.
	require.EqualValues(t, 1, alerts[0].CodeFlowsDocument.Document[1].Region.StartColumn)  // Unspecified so should default to 1.
}

func TestCodeFlowsNoMessage(t *testing.T) {
	builder := defaultBuilder()
	sarif := samples.RequireSARIF(t, "testdata/example-flow-no-message.sarif")
	alerts, err := builder.Build(context.Background(), sarif.Runs[0], "")
	require.Nil(t, err)

	require.Len(t, alerts[0].CodeFlowsDocument.Document, 2)
}

func TestRelatedLocation(t *testing.T) {
	builder := defaultBuilder()
	sarif := samples.RequireSARIF(t, "testdata/example.sarif")
	alerts, err := builder.Build(context.Background(), sarif.Runs[0], "")
	require.Nil(t, err)

	require.Len(t, alerts[1].RelatedLocations, 2)
	require.Equal(t, "src/ParseObject.js", alerts[1].RelatedLocations[0].FilePath)
	require.Equal(t, "src/LiveQueryClient.js", alerts[1].RelatedLocations[1].FilePath)
}

func TestAbsoluteLocation(t *testing.T) {
	builder := defaultBuilder()
	sarif := samples.RequireSARIF(t, "testdata/absolute_locations.sarif")
	alerts, err := builder.Build(context.Background(), sarif.Runs[0], "file:///github/workspace")
	require.Nil(t, err)
	require.Equal(t, "examples/cipher-modes.py", alerts[0].FilePath)
	require.Equal(t, "examples/cipher-modes.py", alerts[0].RelatedLocations[0].FilePath)
	require.Equal(t, "examples/cipher-modes.py", alerts[0].CodeFlowsDocument.Document[0].FilePath)
}

func TestAbsoluteLocationWindows(t *testing.T) {
	builder := defaultBuilder()
	sarif := samples.RequireSARIF(t, "testdata/absolute_locations_windows.sarif")
	alerts, err := builder.Build(context.Background(), sarif.Runs[0], "file:///C:/Documents%20and%20Settings/github/workspace")
	require.Nil(t, err)
	require.Equal(t, "examples/cipher-modes.py", alerts[0].FilePath)
	require.Equal(t, "examples/cipher-modes.py", alerts[0].RelatedLocations[0].FilePath)
	require.Equal(t, "examples/cipher-modes.py", alerts[0].CodeFlowsDocument.Document[0].FilePath)
}

func TestLimit_Results(t *testing.T) {
	sarif := samples.RequireSARIF(t, "../sarif/testdata/example2.sarif")
	lt := limits.LimitsDefault()
	lt.ResPerRunLimit = 1

	builder := NewAlertsBuilder(&ts.Analysis{RepositoryID: testRepoID, ID: testAnalysisID, Rules: defaultRules()}, &lt)
	alerts, err := builder.Build(context.Background(), sarif.Runs[0], "")
	require.NotNil(t, err)
	require.Len(t, err, 1)
	require.NoError(t, UnrecoverableError(err))
	require.Len(t, alerts, 1)
}

func TestLimit_ResultsBySeverity(t *testing.T) {
	sarif := samples.RequireSARIF(t, "../sarif/testdata/severity.sarif")
	lt := limits.LimitsDefault()
	sarif.Runs[0].Results[0].Level = "note"
	sarif.Runs[0].Results[1].Level = "warning"
	sarif.Runs[0].Results[2].Level = "error"

	// No sorting if we consider all results
	builder := NewAlertsBuilder(&ts.Analysis{RepositoryID: testRepoID, ID: testAnalysisID, Rules: defaultRules()}, &lt)
	alerts, err := builder.Build(context.Background(), sarif.Runs[0], "")
	require.Nil(t, err)
	require.Len(t, alerts, 4)
	require.Equal(t, sarif.Runs[0].Results[0].Message.Text, alerts[0].Message)
	require.Equal(t, sarif.Runs[0].Results[1].Message.Text, alerts[1].Message)
	require.Equal(t, sarif.Runs[0].Results[2].Message.Text, alerts[2].Message)
	require.Equal(t, sarif.Runs[0].Results[3].Message.Text, alerts[3].Message)

	// Sort and Filter by severity
	lt.ResPerRunLimit = 3
	builder = NewAlertsBuilder(&ts.Analysis{RepositoryID: testRepoID, ID: testAnalysisID, Rules: defaultRules()}, &lt)
	alerts, err = builder.Build(context.Background(), sarif.Runs[0], "")
	require.NoError(t, UnrecoverableError(err))
	require.Error(t, err)
	require.Len(t, alerts, 3)
	require.Equal(t, ts.SeverityLevelError, alerts[0].SeverityLevel)
	require.Equal(t, sarif.Runs[0].Results[2].Message.Text, alerts[0].Message)
	require.Equal(t, ts.SeverityLevelWarning, alerts[1].SeverityLevel)
	require.Equal(t, sarif.Runs[0].Results[1].Message.Text, alerts[1].Message)
	require.Equal(t, ts.SeverityLevelNote, alerts[2].SeverityLevel)
	require.Equal(t, sarif.Runs[0].Results[0].Message.Text, alerts[2].Message)

	lt.ResPerRunLimit = 2
	builder = NewAlertsBuilder(&ts.Analysis{RepositoryID: testRepoID, ID: testAnalysisID, Rules: defaultRules()}, &lt)
	alerts, err = builder.Build(context.Background(), sarif.Runs[0], "")
	require.NoError(t, UnrecoverableError(err))
	require.Error(t, err)
	require.Len(t, alerts, 2)
	require.Equal(t, ts.SeverityLevelError, alerts[0].SeverityLevel)
	require.Equal(t, ts.SeverityLevelWarning, alerts[1].SeverityLevel)

	// Sort and Filter by security severity
	sarif.Runs[0].Results[0].Level = "note"
	sarif.Runs[0].Results[0].Properties = &v210turboscan.ResultPropertyBag{
		SecuritySeverity: "10.0", // Critical
	}
	sarif.Runs[0].Results[1].Level = "warning"
	sarif.Runs[0].Results[2].Level = "error"
	sarif.Runs[0].Results[2].Properties = &v210turboscan.ResultPropertyBag{
		SecuritySeverity: "5.0", // Medium
	}
	sarif.Runs[0].Results[3].Level = "error"

	lt.ResPerRunLimit = 3
	builder = NewAlertsBuilder(&ts.Analysis{RepositoryID: testRepoID, ID: testAnalysisID, Rules: defaultRules()}, &lt)
	alerts, err = builder.Build(context.Background(), sarif.Runs[0], "")
	require.NoError(t, UnrecoverableError(err))
	require.Error(t, err)
	require.Len(t, alerts, 3)

	require.Equal(t, proto.SecuritySeverity_CRITICAL, alerts[0].SecuritySeverityLevel())
	require.Equal(t, sarif.Runs[0].Results[0].Message.Text, alerts[0].Message)
	require.Equal(t, proto.SecuritySeverity_MEDIUM, alerts[1].SecuritySeverityLevel())
	require.Equal(t, sarif.Runs[0].Results[2].Message.Text, alerts[1].Message)
	require.Equal(t, ts.SeverityLevelError, alerts[2].SeverityLevel)
	require.Equal(t, sarif.Runs[0].Results[3].Message.Text, alerts[2].Message)
}

func TestLimit_CodeFlows(t *testing.T) {
	sarif := samples.RequireSARIF(t, "../sarif/testdata/example2.sarif")

	lt := limits.LimitsDefault()
	builder := NewAlertsBuilder(&ts.Analysis{RepositoryID: testRepoID, ID: testAnalysisID, Rules: defaultRules()}, &lt)
	alerts, err := builder.Build(context.Background(), sarif.Runs[0], "")
	require.Nil(t, err)
	require.Equal(t, "components/camel-http-common/src/main/java/org/apache/camel/http/common/DefaultHttpBinding.java", alerts[0].FilePath)
	require.Len(t, alerts[0].CodeFlowsDocument.Document, 191)

	lt.StepsPerResLimit = 13 // There is a single ThreadFlow with 13 steps
	builder = NewAlertsBuilder(&ts.Analysis{RepositoryID: testRepoID, ID: testAnalysisID, Rules: defaultRules()}, &lt)
	alerts, err = builder.Build(context.Background(), sarif.Runs[0], "")
	require.NotNil(t, err)
	require.NoError(t, UnrecoverableError(err))

	require.Equal(t, "components/camel-http-common/src/main/java/org/apache/camel/http/common/DefaultHttpBinding.java", alerts[0].FilePath)
	require.Len(t, alerts[0].CodeFlowsDocument.Document, 13)
}

func TestLimit_CodeFlowsSmartFilter(t *testing.T) {
	lt := limits.LimitsDefault()
	lt.LocPerResLimit = 1

	// We have smart filtering that considers different init-final locations.
	codeFlows := [][]string{
		{"file1", "file2", "file3"},
		{"file1", "file2", "file4"},
		{"file0", "file2", "file4"},
		{"file1", "file6", "file4"},
		{"file1", "file7", "file4"},
	}

	var flows ts.CodeFlows
	for idx, flow := range codeFlows {
		for stepIdx, step := range flow {
			flows = append(flows, ts.CodeFlow{
				FilePath:        step,
				StepIndex:       uint32(stepIdx),
				CodeFlowIndex:   uint32(idx),
				ThreadFlowIndex: 0,
			})
		}
	}

	// Swap entries to ensure that computing the length of flow works correctly.
	flows[2], flows[5] = flows[5], flows[2]
	flows[3], flows[6] = flows[6], flows[3]

	outFlow := filterCodeFlows(flows, 10)
	require.Len(t, outFlow, 3*3) // 3 flows, 3 steps each

	// We dropped the last flow
	for i := 0; i < len(outFlow); i++ {
		require.Equal(t, flows[i].FilePath, outFlow[i].FilePath)
	}

	// If we have more space, we keep more but not all
	outFlow = filterCodeFlows(flows, 13)
	require.Len(t, outFlow, 12)
}

func TestLimit_CodeFlowsSmartFilter_MultiThread(t *testing.T) {
	// If there are multiple threads, we do simple truncation to the limit
	flows := ts.CodeFlows{
		ts.CodeFlow{FilePath: "file1", ThreadFlowIndex: 0},
		ts.CodeFlow{FilePath: "file2", ThreadFlowIndex: 1},
	}
	outFlow := filterCodeFlows(flows, 1)
	require.Len(t, outFlow, 1) // 3 flows, 3 steps each
}

func TestLimit_RelatedLocations(t *testing.T) {
	sarif := samples.RequireSARIF(t, "testdata/example.sarif")

	lt := limits.LimitsDefault()
	lt.LocPerResLimit = 1
	builder := NewAlertsBuilder(&ts.Analysis{RepositoryID: testRepoID, ID: testAnalysisID, Rules: defaultRules()}, &lt)

	alerts, err := builder.Build(context.Background(), sarif.Runs[0], "")
	require.NotNil(t, err)
	require.NoError(t, UnrecoverableError(err))
	require.Len(t, alerts[1].RelatedLocations, 1)
}

func TestClassification(t *testing.T) {
	builder := defaultBuilder()
	sarif := samples.RequireSARIF(t, "testdata/classification.sarif")
	alerts, err := builder.Build(context.Background(), sarif.Runs[0], "")
	require.Nil(t, err)
	require.Equal(t, "jquery.min.js", alerts[0].FilePath)
	require.Equal(t, ts.FileClassification{"generated"}, alerts[0].FileClassification)

	require.Equal(t, "src/ParseObject.js", alerts[1].FilePath)
	require.Equal(t, ts.FileClassification{}, alerts[1].FileClassification)

	require.Equal(t, "test/promiseUtils.js", alerts[2].FilePath)
	require.Equal(t, ts.FileClassification{"test"}, alerts[2].FileClassification)
}

func TestSnippets(t *testing.T) {
	sarif := samples.RequireSARIF(t, "../sarif/testdata/snippets.sarif")
	builder := defaultBuilder()
	alerts, err := builder.Build(context.Background(), sarif.Runs[0], "")
	require.NotNil(t, err)
	require.NoError(t, UnrecoverableError(err))
	require.Len(t, alerts, 2)
	for _, a := range alerts {
		require.NotNil(t, a.Snippet)
	}
	s0 := alerts[0].Snippet
	require.Equal(t, "func (e AnalysisEnv) Value() (driver.Value, error) {\n\ts, err := e.string()\n\treturn *s, err\n}\n\n", s0.Text)
	require.Equal(t, uint32(48), s0.Region.StartLine)
	require.Equal(t, uint32(52), s0.Region.EndLine)
	require.Equal(t, uint32(1), s0.Region.StartColumn)
	require.Equal(t, uint32(0), s0.Region.EndColumn)
}

func TestBuild_MissingLocation(t *testing.T) {
	sarif := samples.RequireSARIF(t, "../sarif/testdata/missing_location.sarif")
	builder := defaultBuilder()
	_, err := builder.Build(context.Background(), sarif.Runs[0], "")
	require.NotNil(t, err)
	require.Error(t, UnrecoverableError(err))
}

func TestBuild_EndLine(t *testing.T) {
	sarif := samples.RequireSARIF(t, "../sarif/testdata/endline.sarif")
	builder := defaultBuilder()
	_, err := builder.Build(context.Background(), sarif.Runs[0], "")
	// TODO: This will be converted into an error in the future.
	// Therefore, the line below should become:
	//	  require.NotNil(t, err)
	// See https://github.com/github/turboscan/pull/964
	require.Nil(t, err)
}

func TestBuild_NoRelatedLocationMessage(t *testing.T) {
	sarif := samples.RequireSARIF(t, "../sarif/testdata/example-no-relatedlocation-message.sarif")
	builder := defaultBuilder()
	_, err := builder.Build(context.Background(), sarif.Runs[0], "")
	require.Nil(t, err)
}

func TestBuild_RepeatedLogicalAlerts(t *testing.T) {

	// This file contains the actual regression with 4825 results. The logic to
	// skip repeated alerts will discard all physical alerts that map to the same
	// logical alert after considering the first 255.
	s := samples.RequireSARIF(t, "../sarif/testdata/repeated_logical_error.sarif.gz")
	lt := limits.LimitsHuge()
	builder := NewAlertsBuilder(&ts.Analysis{RepositoryID: testRepoID, ID: testAnalysisID, Rules: defaultRules()}, &lt)
	alerts, err := builder.Build(context.Background(), s.Runs[0], "")
	require.Nil(t, err)
	require.Equal(t, 3921, len(alerts))

	// Test the actual logic. Repeat the alert 255 times.
	builder = NewAlertsBuilder(&ts.Analysis{RepositoryID: testRepoID, ID: testAnalysisID, Rules: defaultRules()}, &lt)
	result := s.Runs[0].Results[0]
	for i := 0; i < 255; i++ {
		_, err := builder.BuildAlert(s.Runs[0], i, result, "")
		require.NoError(t, err)
	}
	_, err = builder.BuildAlert(s.Runs[0], 0, result, "")
	require.Error(t, err)

}

func defaultRules() map[string]*ts.Rule {
	// This is a list of all rules used in the examples for the tests.
	rules := make(map[string]*ts.Rule)
	allSID := []string{
		"js/unused-local-variable",
		"js/sql-injection",
		"com.lgtm/java-queries:java/xss",
		"js/inconsistent-use-of-new",
		"js/incorrect-suffix-check",
		"B305",
		"cs/webclient-path-injection",
		"cs/web/missing-token-validation",
		"cs/session-reuse",
		"cs/hardcoded-credentials",
		"cs/hardcoded-connection-string-credentials",
		"cs/web/missing-global-error-handler",
		"cs/xml/insecure-dtd-handling",
		"cs/unvalidated-local-pointer-arithmetic",
		"cs/uncontrolled-format-string",
		"cs/log-forging",
		"cs/xml-injection",
		"cs/sensitive-data-transmission",
		"cs/deserialized-delegate",
		"cs/unsafe-deserialization-untrusted-input",
		"cs/use-of-vulnerable-package",
		"cs/web/broad-cookie-domain",
		"cs/web/disabled-header-checking",
		"cs/sql-injection",
		"cs/inadequate-rsa-padding",
		"cs/command-line-injection",
		"cs/web/xss",
		"cs/web/unvalidated-url-redirection",
		"cs/web/requiressl-not-set",
		"cs/web/debug-binary",
		"cs/ecb-encryption",
		"cs/web/persistent-cookie",
		"cs/ldap-injection",
		"cs/web/missing-x-frame-options",
		"cs/redos",
		"cs/regex-injection",
		"cs/cleartext-storage-of-sensitive-information",
		"cs/web/broad-cookie-path",
		"cs/code-injection",
		"cs/xml/xpath-injection",
		"cs/exposure-of-sensitive-information",
		"cs/web/directory-browse-enabled",
		"cs/resource-injection",
		"cs/path-injection",
		"cs/zipslip",
		"cs/information-exposure-through-exception",
		"cs/assembly-path-injection",
		"cs/insufficient-key-size",
		"cs/weak-encryption",
		"cs/insecure-randomness",
		"cs/user-controlled-bypass",
		"expr",
		"iterator",
		"sub",
		"asi",
		"boss",
		"funcscope",
		"loopfunc",
		"cpp/unsafe-dacl-security-descriptor",
		"cpp/sql-injection",
		"cpp/no-space-for-terminator",
		"cpp/cgi-xss",
		"cpp/badly-bounded-write",
		"cpp/incorrect-string-type-conversion",
		"cpp/potentially-dangerous-function",
		"cpp/dangerous-cin",
		"cpp/dangerous-function-overflow",
		"cpp/uncontrolled-allocation-size",
		"cpp/comparison-with-wider-type",
		"cpp/hresult-boolean-conversion",
		"cpp/suspicious-add-sizeof",
		"cpp/openssl-heartbleed",
		"cpp/upcast-array-pointer-arithmetic",
		"cpp/alloca-in-loop",
		"cpp/pointer-overflow-check",
		"cpp/signed-overflow-check",
		"cpp/bad-addition-overflow-check",
		"cpp/integer-multiplication-cast-to-long",
		"cpp/too-few-arguments",
		"cpp/wrong-number-format-arguments",
		"cpp/wrong-type-format-argument",
		"cpp/overflowing-snprintf",
		"cpp/new-free-mismatch",
		"cpp/summary/lines-of-code",
		"asi",
		"boss",
		"expr",
		"funcscope",
		"iterator",
		"loopfunc",
		"shadow",
		"Stylelint_at-rule-empty-line-before",
		"Stylelint_block-closing-brace-newline-after",
		"Stylelint_block-closing-brace-space-before",
		"Stylelint_block-opening-brace-space-after",
		"Stylelint_block-opening-brace-space-before",
		"Stylelint_color-hex-case",
		"Stylelint_color-hex-length",
		"Stylelint_comment-empty-line-before",
		"Stylelint_declaration-bang-space-before",
		"Stylelint_declaration-block-no-duplicate-properties",
		"Stylelint_declaration-block-no-shorthand-property-overrides",
		"Stylelint_declaration-block-semicolon-space-after",
		"Stylelint_declaration-block-semicolon-space-before",
		"Stylelint_declaration-block-single-line-max-declarations",
		"Stylelint_declaration-block-trailing-semicolon",
		"Stylelint_declaration-colon-space-after",
		"Stylelint_font-family-no-missing-generic-family-keyword",
		"Stylelint_function-comma-space-after",
		"Stylelint_indentation",
		"Stylelint_media-feature-colon-space-after",
		"Stylelint_no-descending-specificity",
		"Stylelint_no-duplicate-selectors",
		"Stylelint_no-missing-end-of-source-newline",
		"Stylelint_number-leading-zero",
		"Stylelint_rule-empty-line-before",
		"Stylelint_selector-combinator-space-after",
		"Stylelint_selector-combinator-space-before",
		"Stylelint_selector-descendant-combinator-no-non-space",
		"Stylelint_selector-list-comma-newline-after",
		"Stylelint_selector-pseudo-element-colon-notation",
		"Stylelint_value-keyword-case",
		"Stylelint_value-list-comma-space-after",
		"sub",
		"undef",
		"py/unreachable-statement",
		"py/unused-import",
		"[unknown-rule]",
	}
	for _, id := range allSID {
		rules[id] = &ts.Rule{
			SarifIdentifier: id,
		}
	}
	return rules
}
func TestBuild_ValidResultGUID(t *testing.T) {
	s := samples.RequireSARIF(t, "../sarif/testdata/result_guid_valid.sarif")
	builder := defaultBuilder()

	alerts, err := builder.Build(context.Background(), s.Runs[0], "")
	require.Nil(t, err)
	require.Nil(t, alerts[0].GUID)
	require.Equal(t, "e4685d66-187d-45e4-81d8-91eb4038d742", *alerts[1].GUID)
	require.Equal(t, "a397a309-1d24-46ee-a2fe-c553f1c91fc8", *alerts[2].GUID)
}

func TestBuild_ValidResultInvalidGUID(t *testing.T) {
	s := samples.RequireSARIF(t, "../sarif/testdata/result_guid_invalid.sarif")
	require.Equal(t, "this is not a guid", s.Runs[0].Results[2].Guid)
	builder := defaultBuilder()

	alerts, err := builder.Build(context.Background(), s.Runs[0], "")
	require.Nil(t, err)
	require.Nil(t, alerts[0].GUID)
	require.Equal(t, "e4685d66-187d-45e4-81d8-91eb4038d742", *alerts[1].GUID)
	// Invalid format GUIDs are ignored and not persisted to the database
	require.Nil(t, alerts[2].GUID)
}

func TestBuild_SecuritySeverity(t *testing.T) {
	s := samples.RequireSARIF(t, "../sarif/testdata/security-severity.sarif")
	builder := defaultBuilder()

	alerts, err := builder.Build(context.Background(), s.Runs[0], "")
	require.Nil(t, err)
	// Check alert that defaults to the rule security severity
	require.Equal(t, 7.8, *alerts[0].SecuritySeverity)
	require.Equal(t, proto.SecuritySeverity_HIGH, alerts[0].SecuritySeverityLevel())
	// Check alert that overrides the rule security severity
	require.Equal(t, 10.0, *alerts[1].SecuritySeverity)
	require.Equal(t, proto.SecuritySeverity_CRITICAL, alerts[1].SecuritySeverityLevel())
}

func TestBuild_InvalidArtifactLocation(t *testing.T) {
	s := samples.RequireSARIF(t, "../sarif/testdata/invalid_artifact_location.sarif")
	builder := defaultBuilder()

	_, err := builder.Build(context.Background(), s.Runs[0], "")
	require.Error(t, err)
}

func TestBuild_UnrecoverableArchivalError(t *testing.T) {
	s := samples.RequireSARIF(t, "../sarif/testdata/invalid_artifact_location.sarif")
	builder := defaultBuilder()

	_, err := builder.Build(context.Background(), s.Runs[0], "")
	require.NotNil(t, err)
	require.Len(t, err, 1)
	require.Error(t, UnrecoverableError(err))
	require.NoError(t, UnrecoverableArchivalError(err))
}

func TestBuild_UsesCheckoutURIFromRunOverProvidedOne(t *testing.T) {
	s := samples.RequireSARIF(t, "../sarif/testdata/checkouturi.sarif")
	builder := defaultBuilder()

	alerts, err := builder.Build(context.Background(), s.Runs[0], "file:///github/workspace")
	require.NoError(t, err)
	require.Equal(t, 1, len(alerts))
	require.Equal(t, "include/geometry/BoundingBox.h", alerts[0].FilePath)
}
