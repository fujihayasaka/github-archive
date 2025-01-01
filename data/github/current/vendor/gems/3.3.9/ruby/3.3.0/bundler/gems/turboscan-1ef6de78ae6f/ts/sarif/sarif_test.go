package sarif_test

import (
	"context"
	"fmt"
	"sort"
	"strings"
	"testing"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/proto"
	"github.com/github/turboscan/ts/sarif"
	"github.com/github/turboscan/ts/sarif/samples"
	v2_1_0 "github.com/github/turboscan/ts/sarif/v2_1_0_turboscan"
	"github.com/stretchr/testify/require"
)

const tagsPerRuleLimit = 5

func TestSuppressed(t *testing.T) {
	r := &v2_1_0.Result{}

	// No suppressions
	suppressed, err := sarif.Suppressed(r)
	require.NoError(t, err)
	require.False(t, suppressed)

	// Empty set of suppressions
	r.Suppressions = [](*v2_1_0.Suppression){}
	suppressed, err = sarif.Suppressed(r)
	require.NoError(t, err)
	require.False(t, suppressed)

	// Single suppression - no status
	r.Suppressions = [](*v2_1_0.Suppression){&v2_1_0.Suppression{}}
	suppressed, err = sarif.Suppressed(r)
	require.NoError(t, err)
	require.True(t, suppressed)

	// Single suppression - rejected
	r.Suppressions = [](*v2_1_0.Suppression){&v2_1_0.Suppression{State: "rejected"}}
	suppressed, err = sarif.Suppressed(r)
	require.NoError(t, err)
	require.False(t, suppressed)

	// Single suppression - accepted
	r.Suppressions = [](*v2_1_0.Suppression){&v2_1_0.Suppression{State: "accepted"}}
	suppressed, err = sarif.Suppressed(r)
	require.NoError(t, err)
	require.True(t, suppressed)

	// Multiple suppressions - rejected + accepted
	r.Suppressions = [](*v2_1_0.Suppression){
		&v2_1_0.Suppression{State: "rejected"},
		&v2_1_0.Suppression{State: "accepted"},
	}
	suppressed, err = sarif.Suppressed(r)
	require.NoError(t, err)
	require.True(t, suppressed)

	// Multiple suppressions - accepted + rejected
	r.Suppressions = [](*v2_1_0.Suppression){
		&v2_1_0.Suppression{State: "rejected"},
		&v2_1_0.Suppression{State: "accepted"},
	}
	suppressed, err = sarif.Suppressed(r)
	require.NoError(t, err)
	require.True(t, suppressed)

	// Invalid suppression values - wrong string
	r.Suppressions = [](*v2_1_0.Suppression){&v2_1_0.Suppression{State: "abc"}}
	_, err = sarif.Suppressed(r)
	require.Error(t, err)

	// Invalid suppression values - wrong type
	r.Suppressions = [](*v2_1_0.Suppression){&v2_1_0.Suppression{State: 324}}
	_, err = sarif.Suppressed(r)
	require.Error(t, err)

}

func TestRuleFromResult(t *testing.T) {
	var actual *v2_1_0.Rule
	var err error
	var tcInd v2_1_0.ToolComponentIndicator

	s := samples.RequireSARIF(t, "testdata/rules.sarif")
	run := s.Runs[0]
	expected := run.Tool.Driver.Rules[0]

	// 0. By RuleId
	actual, tcInd, err = sarif.RuleFromResult(run, run.Results[0])
	require.NoError(t, err)
	require.Equal(t, expected, actual)
	require.True(t, tcInd.IsDriver())

	// Locally modify the data in run.results to include an invalid id
	run.Results[0].RuleId = "rule_not_in_sarif"
	actual, tcInd, err = sarif.RuleFromResult(run, run.Results[0])
	require.NoError(t, err)
	require.Equal(t, run.Results[0].RuleId, actual.Id)
	require.True(t, tcInd.IsDriver())

	// 1. By RuleIndex
	actual, tcInd, err = sarif.RuleFromResult(run, run.Results[1])
	require.NoError(t, err)
	require.Equal(t, expected, actual)
	require.True(t, tcInd.IsDriver())

	// Locally modify the data in run.results to include an invalid index
	run.Results[1].RuleIndex = 10
	_, _, err = sarif.RuleFromResult(run, run.Results[1])
	require.Error(t, err)
	require.True(t, tcInd.IsDriver())

	// 2. By Rule.id
	actual, tcInd, err = sarif.RuleFromResult(run, run.Results[2])
	require.NoError(t, err)
	require.Equal(t, expected, actual)
	require.True(t, tcInd.IsDriver())

	// Locally modify the data in run.results to include a hierarchical
	run.Results[2].Rule.Id += "/abc"
	actual, tcInd, err = sarif.RuleFromResult(run, run.Results[2])
	require.NoError(t, err)
	require.Equal(t, expected, actual)
	require.True(t, tcInd.IsDriver())

	// 3. By Rule.index
	actual, tcInd, err = sarif.RuleFromResult(run, run.Results[3])
	require.NoError(t, err)
	require.Equal(t, expected, actual)
	require.True(t, tcInd.IsDriver())
}

func TestRuleFromResultWithExtensions(t *testing.T) {
	var actual *v2_1_0.Rule
	var err error
	var tcInd v2_1_0.ToolComponentIndicator

	s := samples.RequireSARIF(t, "testdata/rulesExtensions.sarif")
	run := s.Runs[0]
	expected := run.Tool.Extensions[0].Rules[0]
	expInd := v2_1_0.ToolComponentIndicator(0)

	// 0. By RuleId
	actual, tcInd, err = sarif.RuleFromResult(run, run.Results[0])
	require.NoError(t, err)
	require.Equal(t, expected, actual)
	require.Equal(t, expInd, tcInd)

	// Locally modify the data in run.results to include an invalid id
	run.Results[0].RuleId = "rule_not_in_sarif"
	actual, tcInd, err = sarif.RuleFromResult(run, run.Results[0])
	require.NoError(t, err)
	require.Equal(t, run.Results[0].RuleId, actual.Id)
	require.Equal(t, expInd, tcInd)

	// 1. By RuleIndex
	actual, tcInd, err = sarif.RuleFromResult(run, run.Results[1])
	require.NoError(t, err)
	require.Equal(t, expected, actual)
	require.Equal(t, expInd, tcInd)

	// Locally modify the data in run.results to include an invalid index
	run.Results[1].RuleIndex = 10
	_, _, err = sarif.RuleFromResult(run, run.Results[1])
	require.Error(t, err)

	// 2. By Rule.id
	actual, tcInd, err = sarif.RuleFromResult(run, run.Results[2])
	require.NoError(t, err)
	require.Equal(t, expected, actual)
	require.Equal(t, expInd, tcInd)

	// Locally modify the data in run.results to include a hierarchical
	run.Results[2].Rule.Id += "/abc"
	actual, tcInd, err = sarif.RuleFromResult(run, run.Results[2])
	require.NoError(t, err)
	require.Equal(t, expected, actual)
	require.Equal(t, expInd, tcInd)

	// 3. By Rule.index
	actual, tcInd, err = sarif.RuleFromResult(run, run.Results[3])
	require.NoError(t, err)
	require.Equal(t, expected, actual)
	require.Equal(t, expInd, tcInd)

	actual, tcInd, err = sarif.RuleFromResult(run, run.Results[4])
	require.NoError(t, err)
	require.Equal(t, run.Tool.Extensions[0].Rules[1], actual)
	require.Equal(t, expInd, tcInd)
}

func TestRuleFromSarifRule(t *testing.T) {
	tool := ts.ToolFromCanonicalName("CodeQL")
	s := samples.RequireSARIF(t, "testdata/rules.sarif")
	sarifRule := s.Runs[0].Tool.Driver.Rules[0]

	rule, tagsAboveLimit, err := sarif.RuleFromSarifRule(sarifRule, tool, tagsPerRuleLimit)
	require.NoError(t, err)

	require.Equal(t, sarifRule.Id, rule.SarifIdentifier)
	require.Equal(t, sarifRule.Name, rule.Name)
	require.Equal(t, sarifRule.ShortDescription.Text, rule.ShortDescription)
	require.Equal(t, sarifRule.FullDescription.Text, rule.FullDescription)
	require.Equal(t, ts.SeverityLevelWarning, rule.SeverityLevel)
	require.Nil(t, rule.SecuritySeverity)
	require.Equal(t, sarifRule.Properties.Precision, rule.PrecisionLevel.String())
	require.Equal(t, sarifRule.Help.Markdown, rule.Help)
	require.Equal(t, sarifRule.HelpUri, rule.HelpURI)
	require.Equal(t, sarifRule.Properties.Tags[0], rule.Tags[0].Tag)
	require.Lessf(t, tagsAboveLimit, 0, fmt.Sprintf("zero/negative value is expected for 'tagsAboveLimit' if the rule tags are within the limit of %d", tagsPerRuleLimit))
}

func TestRuleFromSarifRuleWithExtensions(t *testing.T) {
	tool := ts.ToolFromCanonicalName("CodeQL")
	s := samples.RequireSARIF(t, "testdata/rulesExtensions.sarif")
	sarifRule := s.Runs[0].Tool.Extensions[0].Rules[0]

	rule, _, err := sarif.RuleFromSarifRule(sarifRule, tool, tagsPerRuleLimit)
	require.NoError(t, err)

	require.Equal(t, sarifRule.Id, rule.SarifIdentifier)
	require.Equal(t, sarifRule.Name, rule.Name)
	require.Equal(t, sarifRule.ShortDescription.Text, rule.ShortDescription)
	require.Equal(t, sarifRule.FullDescription.Text, rule.FullDescription)
	require.Equal(t, ts.SeverityLevelWarning, rule.SeverityLevel)
	require.Nil(t, rule.SecuritySeverity)
	require.Equal(t, sarifRule.Properties.Precision, rule.PrecisionLevel.String())
	require.Equal(t, sarifRule.Help.Markdown, rule.Help)
	require.Equal(t, sarifRule.HelpUri, rule.HelpURI)
	require.Equal(t, sarifRule.Properties.Tags[0], rule.Tags[0].Tag)
}

func TestRuleFromSarifRuleWithSecuritySeverity(t *testing.T) {
	tool := ts.ToolFromCanonicalName("CodeQL")
	s := samples.RequireSARIF(t, "testdata/security-severity.sarif")
	sarifRule := s.Runs[0].Tool.Driver.Rules[0]

	rule, _, err := sarif.RuleFromSarifRule(sarifRule, tool, tagsPerRuleLimit)
	require.NoError(t, err)

	require.Equal(t, sarifRule.Id, rule.SarifIdentifier)
	require.Equal(t, sarifRule.Name, rule.Name)
	require.Equal(t, sarifRule.ShortDescription.Text, rule.ShortDescription)
	require.Equal(t, sarifRule.FullDescription.Text, rule.FullDescription)
	require.Equal(t, ts.SeverityLevelError, rule.SeverityLevel)
	require.Equal(t, 7.8, *rule.SecuritySeverity)
	require.Equal(t, proto.SecuritySeverity_HIGH, rule.SecuritySeverityLevel())
	require.Equal(t, sarifRule.Properties.Precision, rule.PrecisionLevel.String())
	require.Equal(t, sarifRule.HelpUri, rule.HelpURI)
}

func TestRuleFromSarifRuleTruncateHelp(t *testing.T) {
	tool := ts.ToolFromCanonicalName("CodeQL")

	shortEnoughMarkdown := strings.Repeat("?", 64*1024)
	multiformatMessageString := v2_1_0.MultiformatMessageString{Markdown: shortEnoughMarkdown}
	sarifRule := v2_1_0.Rule{Help: &multiformatMessageString}
	rule, _, err := sarif.RuleFromSarifRule(&sarifRule, tool, tagsPerRuleLimit)
	require.NoError(t, err)
	require.Equal(t, rule.Help, shortEnoughMarkdown)

	tooLongMarkdown := strings.Repeat("?", 64*1024+1)
	multiformatMessageString = v2_1_0.MultiformatMessageString{Markdown: tooLongMarkdown}
	sarifRule = v2_1_0.Rule{Help: &multiformatMessageString}
	rule, _, err = sarif.RuleFromSarifRule(&sarifRule, tool, tagsPerRuleLimit)
	require.NoError(t, err)
	require.Equal(t, rule.Help, shortEnoughMarkdown)
}

func TestRuleFromSarifRuleTruncateTags(t *testing.T) {
	tool := ts.ToolFromCanonicalName("CodeQL")
	inRule := &v2_1_0.Rule{
		Name: "long-tags",
		Properties: &v2_1_0.ReportingDescriptorPropertyBag{
			Tags: []string{
				strings.Repeat("a", 1024),
			},
		},
	}
	outRule, _, err := sarif.RuleFromSarifRule(inRule, tool, tagsPerRuleLimit)
	require.NoError(t, err)
	tags, err := outRule.GetTags()
	require.NoError(t, err)
	require.Len(t, tags, 1)
	require.Len(t, tags[0], 255)
}

func TestRuleFromSarifRuleRemoveManyTags(t *testing.T) {
	tool := ts.ToolFromCanonicalName("CodeQL")
	inRule := &v2_1_0.Rule{
		Name: "many-tags",
		Properties: &v2_1_0.ReportingDescriptorPropertyBag{
			Tags: []string{
				"CVE-2021", "Apple", "CVE-2009", "CVE-2020", "CVE-2002", "trunk", "demo-app-server",
			},
		},
	}
	outRule, tagsAboveLimit, err := sarif.RuleFromSarifRule(inRule, tool, tagsPerRuleLimit)
	require.NoError(t, err)
	require.Equal(t, len(inRule.Properties.Tags)-tagsPerRuleLimit, tagsAboveLimit)
	tags, err := outRule.GetTags()
	require.NoError(t, err)
	require.Len(t, tags, tagsPerRuleLimit)
	require.Truef(t, sort.SliceIsSorted(tags, func(i, j int) bool { return tags[i] < tags[j] }), "outRule tags should be alphabetically sorted")
}

func TestRuleFromSarifRuleTruncateName(t *testing.T) {
	tool := ts.ToolFromCanonicalName("CodeQL")
	inRule := &v2_1_0.Rule{
		Name: strings.Repeat("a", 1024),
	}
	outRule, _, err := sarif.RuleFromSarifRule(inRule, tool, tagsPerRuleLimit)
	require.NoError(t, err)
	require.Len(t, outRule.Name, 255)
}

func TestRuleFromSarifRuleTagsAreCaseInsensitive(t *testing.T) {
	tool := ts.ToolFromCanonicalName("CodeQL")
	sarifRule := &v2_1_0.Rule{Properties: &v2_1_0.ReportingDescriptorPropertyBag{Tags: []string{"blue", "Blue", "red"}}}

	rule, tagsAboveLimit, err := sarif.RuleFromSarifRule(sarifRule, tool, tagsPerRuleLimit)
	require.NoError(t, err)

	l, err := rule.GetTags()
	require.NoError(t, err)
	require.Len(t, l, 2)
	require.LessOrEqualf(t, tagsAboveLimit, 0, fmt.Sprintf("zero/negative value is expected for 'tagsAboveLimit' if the rule tags are within the limit of %d", tagsPerRuleLimit))
}

func TestGetRulesExtensions(t *testing.T) {
	s := samples.RequireSARIF(t, "testdata/exampleExtensions.sarif")

	rules, err := sarif.GetRules(s.Runs[0])
	require.NoError(t, err)
	require.Len(t, rules, 2)

	require.Equal(t, v2_1_0.ToolComponentIndicator(v2_1_0.ToolComponentDriver), rules["auto-generated-rule-gjkwnfey"].ToolComponentIndicator)
	require.Equal(t, v2_1_0.ToolComponentIndicator(0), rules["auto-generated-extension-rule-04st5lam"].ToolComponentIndicator)
}

func TestGetRules(t *testing.T) {
	s := samples.RequireSARIF(t, "testdata/rules.sarif")

	rules, err := sarif.GetRules(s.Runs[0])
	require.NoError(t, err)
	require.Len(t, rules, 2)

	require.Equal(t, v2_1_0.ToolComponentIndicator(v2_1_0.ToolComponentDriver), rules["js/unused-local-variable"].ToolComponentIndicator)
	require.Equal(t, v2_1_0.ToolComponentIndicator(v2_1_0.ToolComponentDriver), rules["com.lgtm/python-queries:py/unnecessary-pass"].ToolComponentIndicator)
}

func TestPathFromSARIFURI(t *testing.T) {
	relativePath, err := sarif.URIToPath("file:///foo/bar", "file:///foo")
	require.NoError(t, err)
	require.Equal(t, "bar", relativePath)

	relativePath, err = sarif.URIToPath("file:///foo/bar", "file:///foo/")
	require.NoError(t, err)
	require.Equal(t, "bar", relativePath)

	relativePath, err = sarif.URIToPath("file:///foo/bar", "file:///baz/")
	require.NoError(t, err)
	require.Equal(t, "file:///foo/bar", relativePath)

	relativePath, err = sarif.URIToPath("file:///foo/bar", "file:///foo-src")
	require.NoError(t, err)
	require.Equal(t, "file:///foo/bar", relativePath)

	relativePath, err = sarif.URIToPath("file:///foo", "file:///foo")
	require.NoError(t, err)
	require.Equal(t, "", relativePath)

	relativePath, err = sarif.URIToPath("file:///foo/", "file:///foo")
	require.NoError(t, err)
	require.Equal(t, "", relativePath)

	relativePath, err = sarif.URIToPath("file:///foo", "file:///foo/")
	require.NoError(t, err)
	require.Equal(t, "", relativePath)

	relativePath, err = sarif.URIToPath("file://some-server/horrendus-unc-path/a-file", "file://some-server/horrendus-unc-path")
	require.NoError(t, err)
	require.Equal(t, "a-file", relativePath)

	relativePath, err = sarif.URIToPath("https://github.com/AppThreat/sast-scan/blob/3e6c6da5e981cf51c39312ed0665f3d6d49ee042/a/path/to/a/file.py", "https://github.com/AppThreat/sast-scan/blob/3e6c6da5e981cf51c39312ed0665f3d6d49ee042")
	require.NoError(t, err)
	require.Equal(t, "a/path/to/a/file.py", relativePath)
}

func TestConvertSarifNotificationLocationsToAnalysisMessageLocations(t *testing.T) {
	notification := &v2_1_0.Notification{
		Locations: []*v2_1_0.Location{
			{
				PhysicalLocation: &v2_1_0.PhysicalLocation{
					ArtifactLocation: &v2_1_0.ArtifactLocation{
						Uri: "file:///foo/bar",
					},
					Region: &v2_1_0.Region{
						StartLine:   1,
						EndLine:     1,
						StartColumn: 2,
						EndColumn:   2,
					},
				},
			},
		},
	}

	locations := sarif.ConvertSarifNotificationLocationsToAnalysisMessageLocations(notification.Locations)
	require.Len(t, locations, 1)
	require.Equal(t, "file:///foo/bar", locations[0].FilePath)
	require.Equal(t, 1, locations[0].StartLine)
	require.Equal(t, 1, locations[0].EndLine)
	require.Equal(t, 2, locations[0].StartColumn)
	require.Equal(t, 2, locations[0].EndColumn)
}

func TestGetCodeqlTelemetryDiagnostics(t *testing.T) {
	s := samples.RequireSARIF(t, "testdata/codeql_telemetry.sarif")

	telemetryDiagnostics, err := sarif.GetCodeqlTelemetryDiagnostics(context.Background(), s)
	require.NoError(t, err)

	require.Len(t, telemetryDiagnostics, 2)

	for _, td := range telemetryDiagnostics {
		// Test tool
		require.Equal(t, "CodeQL", td.Run.Tool.Driver.Name)
		// Test tool components
		require.Equal(t, "CodeQL", td.ToolComponent.Name)
	}

	// Test reporting descriptors
	require.Equal(t, "py/diagnostics/recursion-error", telemetryDiagnostics[0].ReportingDescriptor.Id)
	require.Equal(t, "ruby/parse-error", telemetryDiagnostics[1].ReportingDescriptor.Id)

	// Test notifications
	require.Equal(t, "maximum recursion depth exceeded while calling a Python object", telemetryDiagnostics[0].Notification.Message.Text)
	require.Equal(
		t,
		"A parse error occurred. Check the syntax of the file. If the file is invalid, correct the error or "+
			"[exclude](https://docs.github.com/en/code-security/code-scanning/"+
			"automatically-scanning-your-code-for-vulnerabilities-and-errors/customizing-code-scanning) the file from analysis.",
		telemetryDiagnostics[1].Notification.Message.Text)
}

func TestGetCodeqlTelemetryDiagnostics_codeqlVersionTooLow(t *testing.T) {
	s := samples.RequireSARIF(t, "testdata/codeql_telemetry.sarif")
	s.Runs[0].Tool.Driver.SemanticVersion = "2.12.1"

	telemetryDiagnostics, err := sarif.GetCodeqlTelemetryDiagnostics(context.Background(), s)
	require.NoError(t, err)

	require.Len(t, telemetryDiagnostics, 0)
}
