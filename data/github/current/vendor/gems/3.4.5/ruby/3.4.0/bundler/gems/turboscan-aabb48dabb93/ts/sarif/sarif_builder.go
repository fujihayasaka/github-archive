package sarif

import (
	"encoding/json"
	"fmt"
	"net/url"
	"sort"
	"strconv"
	"strings"

	"github.com/pkg/errors"

	"github.com/github/turboscan/ts"
	v210 "github.com/github/turboscan/ts/sarif/v2_1_0_turboscan"
)

type BuildSarifOpts struct {
	RepoHTMLURL            string
	AlertAPIURL            string
	Indent                 bool
	UseRuleIndex           bool
	ForceDefaultsRulesOnly bool
}

func NewSarif() *v210.SARIF210ForGitHubCodeScanning {
	sarif := &v210.SARIF210ForGitHubCodeScanning{}
	sarif.Schema = "https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json"
	sarif.Version = "2.1.0"
	return sarif
}

// BuildSarif returns a validated SARIF string from the given analysis.
func BuildSarif(analysis *ts.Analysis, opts BuildSarifOpts) (string, error) {
	sarif, err := buildSarif(analysis, opts)
	if err != nil {
		return "", err
	}

	var data []byte
	if opts.Indent {
		data, err = json.MarshalIndent(sarif, "", " ")
	} else {
		data, err = json.Marshal(sarif)
	}
	if err != nil {
		return "", err
	}

	return string(data), nil
}

func buildSarif(analysis *ts.Analysis, opts BuildSarifOpts) (*v210.SARIF210ForGitHubCodeScanning, error) {
	sarif := NewSarif()

	runs, err := buildRun(analysis, opts)
	if err != nil {
		return nil, err
	}
	sarif.Runs = runs

	return sarif, nil
}

// buildRun converts an Analysis into a SARIF Run.
// Conceptually, performs the opposite operations from builder.Build.
func buildRun(analysis *ts.Analysis, opts BuildSarifOpts) ([]*v210.Run, error) {
	run := &v210.Run{}

	if analysis == nil {
		return nil, errors.New("analysis can't be nil")
	}

	if opts.RepoHTMLURL != "" {
		vcd := &v210.VersionControlDetails{
			RepositoryUri: opts.RepoHTMLURL,
			RevisionId:    analysis.CommitOid.String(),
			Branch:        string(analysis.Ref),
		}
		run.VersionControlProvenance = append(run.VersionControlProvenance, vcd)
	}
	run.Conversion = &v210.Conversion{}
	run.Conversion.Tool = &v210.Tool{}
	run.Conversion.Tool.Driver = &v210.ToolComponent{}
	run.Conversion.Tool.Driver.Name = "GitHub Code Scanning"

	run.AutomationDetails = &v210.RunAutomationDetails{}
	run.AutomationDetails.Id = analysis.Category.String() + "/" + analysis.RunID

	tool, indexes, err := buildTool(analysis.Tool, analysis.ToolVersion, analysis.ToolVersions, analysis.Rules, opts)
	if err != nil {
		return nil, err
	}
	run.Tool = tool

	results, err := buildResults(analysis.PhysicalAlerts, analysis.Rules, indexes, opts.AlertAPIURL, opts.UseRuleIndex)
	if err != nil {
		return nil, err
	}
	run.Results = results
	run.Artifacts = BuildArtifacts(results)
	codeqlConfig := buildCodeQLConfigSummary(analysis)
	if codeqlConfig != nil {
		run.Properties = &v210.RunPropertyBag{CodeqlConfigSummary: codeqlConfig}
	}

	return []*v210.Run{run}, nil
}

type ruleIndex struct {
	ruleIndex          int
	toolComponentIndex int
}

func buildTool(tool *ts.Tool, toolVersion *ts.ToolVersion, toolVersions []*ts.ToolVersion, rulesMap map[string]*ts.Rule, opts BuildSarifOpts) (*v210.Tool, map[ts.RuleID]ruleIndex, error) {
	t := &v210.Tool{}
	t.Driver = &v210.ToolComponent{}

	t.Driver.Name = tool.CanonicalName.String()
	if toolVersion.FullName != "" {
		t.Driver.FullName = toolVersion.FullName
	}
	t.Driver.Version = toolVersion.Version
	t.Driver.SemanticVersion = toolVersion.SemanticVersion
	t.Extensions = make([]*v210.ToolComponent, 0, len(toolVersions))

	if !tool.IsInternalGUID {
		t.Driver.Guid = tool.GUID
	}

	ruleIndices := make(map[ts.RuleID]ruleIndex)
	extensionIndices := make(map[ts.ToolVersionID]int)
	extensionsMap := make(map[ts.ToolVersionID]*v210.ToolComponent)

	for _, tv := range toolVersions {
		// ignore driver version
		if tv.ID != toolVersion.ID {
			extensionIndices[tv.ID] = len(t.Extensions)
			tc := &v210.ToolComponent{
				Name:            tv.Name.String(),
				SemanticVersion: tv.SemanticVersion,
				Version:         tv.Version,
			}
			if tv.FullName != "" {
				tc.FullName = tv.FullName
			}
			if tv.IsCodeQLModelPack {
				tc.Properties = &v210.PropertyBag{
					AdditionalProperties: map[string]interface{}{"isCodeQLModelPack": true},
				}
			}
			t.Extensions = append(t.Extensions, tc)
			extensionsMap[tv.ID] = tc
		}
	}

	// Convert rules to a stable slice
	rules := make([]*ts.Rule, 0, len(rulesMap))
	for _, r := range rulesMap {
		rules = append(rules, r)
	}
	sort.Slice(rules, func(i, j int) bool { return rules[i].SarifIdentifier < rules[j].SarifIdentifier })

	dr, err := DefaultRuleMetadataAugmentor()
	if err != nil {
		return nil, nil, err
	}
	rm := dr.DefaultRulesDataByTool(tool.CanonicalName.String())

	for _, rule := range rules {
		var r *v210.ReportingDescriptor
		var err error

		if opts.ForceDefaultsRulesOnly {
			// Don't add any of the ts.Rule data to the sarif rule
			// this will be populated by the default definitions
			if d, ok := rm[rule.SarifIdentifier]; ok {
				r = &v210.ReportingDescriptor{
					Id: rule.SarifIdentifier,
				}
				augmentRule(r, d)
			} else {
				continue
			}
		} else {
			r, err = buildRule(rule)
			if err != nil {
				return nil, nil, err
			}
		}

		// first check if the rule was defined in an extension
		var target *v210.ToolComponent
		target, found := extensionsMap[rule.DefiningToolVersionID]
		if found {
			ruleIndices[rule.ID] = ruleIndex{
				ruleIndex:          len(target.Rules),
				toolComponentIndex: extensionIndices[rule.DefiningToolVersionID],
			}
		} else {
			target = t.Driver
			ruleIndices[rule.ID] = ruleIndex{
				ruleIndex:          len(target.Rules),
				toolComponentIndex: v210.ToolComponentDriver,
			}
		}
		target.Rules = append(target.Rules, r)
	}

	return t, ruleIndices, nil
}

func buildRule(rule *ts.Rule) (*v210.ReportingDescriptor, error) {
	r := &v210.ReportingDescriptor{
		Id:   rule.SarifIdentifier,
		Name: rule.Name,
	}

	r.Properties = &v210.ReportingDescriptorPropertyBag{}
	r.ShortDescription = &v210.MultiformatMessageString{Text: rule.ShortDescription}
	r.FullDescription = &v210.MultiformatMessageString{Text: rule.FullDescription}
	r.DefaultConfiguration = &v210.ReportingConfiguration{Level: strings.ToLower(rule.SeverityLevel.String())}
	if rule.Help != "" {
		r.Help = &v210.MultiformatMessageString{
			Text:     rule.Help,
			Markdown: rule.Help,
		}
	}
	r.HelpUri = rule.HelpURI
	if rule.QueryURI != "" {
		r.Properties.QueryURI = rule.QueryURI
	}
	tags, err := rule.GetTags()
	if err != nil {
		return nil, err
	}
	if len(tags) > 0 {
		sort.Strings(tags)
		r.Properties.Tags = append(r.Properties.Tags, tags...)
	}

	if rule.PrecisionLevel != ts.PrecisionLevelUnknown {
		r.Properties.Precision = rule.PrecisionLevel.String()
	}

	if rule.SecuritySeverity != nil {
		r.Properties.SecuritySeverity = strconv.FormatFloat(*rule.SecuritySeverity, 'f', -1, 64)
	}

	return r, nil
}

func buildResults(alerts []*ts.PhysicalAlert, rulesMap map[string]*ts.Rule, ruleIndices map[ts.RuleID]ruleIndex, alertAPIUrl string, useRuleIndex bool) ([]*v210.Result, error) {
	results := []*v210.Result{}

	for _, pa := range alerts {
		la := pa.LogicalAlert

		// The rule sarif identifier is not stored directly in the database, so we need to populate it explicitly
		// we do so directly from the logical alert.
		// Technically the logical alert and physical alert could have different rules,
		// but they must have the same sarif identifier
		pa.RuleSarifIdentifier = la.Rule.SarifIdentifier

		result := &v210.Result{}
		result.Properties = &v210.ResultPropertyBag{}
		results = append(results, result)

		if pa.GUID != nil {
			result.Guid = *pa.GUID
		}
		result.CorrelationGuid = la.GUID
		result.Properties.GithubAlertNumber = int(la.Number)
		if alertAPIUrl != "" {
			result.Properties.GithubAlertUrl = fmt.Sprintf("%s/%d", alertAPIUrl, la.Number)
		}

		result.Rule = &v210.ReportingDescriptorReference{}
		result.Rule.Id = pa.RuleSarifIdentifier
		result.RuleId = result.Rule.Id
		// do not include ruleIndex in the output as it will be included in the rule below
		result.RuleIndex = -1

		if indexes, found := ruleIndices[pa.RuleID]; found {
			result.Rule.Index = indexes.ruleIndex
			if indexes.toolComponentIndex >= 0 {
				result.Rule.ToolComponent = &v210.ToolComponentReference{}
				result.Rule.ToolComponent.Index = indexes.toolComponentIndex
			}
		}
		if useRuleIndex {
			result.RuleIndex = result.Rule.Index
		}

		rule := rulesMap[pa.RuleSarifIdentifier]
		ruleHasSecuritySeverity := rule != nil && rule.SecuritySeverity != nil
		resultHasSecuritySeverity := pa.SecuritySeverity != nil
		resultHasDifferentSecuritySeverity := resultHasSecuritySeverity && (!ruleHasSecuritySeverity || *rule.SecuritySeverity != *pa.SecuritySeverity)

		if resultHasDifferentSecuritySeverity {
			result.Properties.SecuritySeverity = fmt.Sprintf("%f", *pa.SecuritySeverity)
		}

		result.Level = strings.ToLower(pa.SeverityLevel.String())
		result.PartialFingerprints = make(map[string]string)
		result.PartialFingerprints["primaryLocationLineHash"] = pa.Fingerprint

		result.Message = &v210.Message{}
		result.Message.Text = pa.Message
		// Message is mandatory for SARIF parsing, so we set a default if it wasnt specified (old data).
		if result.Message.Text == "" {
			result.Message.Text = "Empty message"
		}

		result.Message.Markdown = pa.MessageMarkdown

		result.Locations = append(result.Locations, &v210.Location{
			PhysicalLocation: &v210.PhysicalLocation{
				ArtifactLocation: BuildArtifactLocation(pa.FilePath),
				Region:           BuildRegion(pa.Region),
			},
		})

		for _, relatedLocation := range pa.RelatedLocations {
			result.RelatedLocations = append(result.RelatedLocations, &v210.Location{
				Id:      int(relatedLocation.ReplacementIndex),
				Message: &v210.Message{Text: relatedLocation.Message},
				PhysicalLocation: &v210.PhysicalLocation{
					ArtifactLocation: BuildArtifactLocation(relatedLocation.FilePath),
					Region:           BuildRegion(relatedLocation.Region),
				},
			})
		}

		// We do not distinguish between different kinds of suppressions,
		// so we just add a single accepted state if the alert is suppressed.
		if pa.Suppressed {
			result.Suppressions = []*v210.Suppression{{State: "accepted"}}
		}

		result.CodeFlows = BuildCodeFlows(pa.CodeFlowsDocument)
	}

	return results, nil
}

func BuildRegion(region ts.Region) *v210.Region {
	// We use the empty region {0, 0, 0, 0} to denote the absence of the region property.
	// So if that is passed in then we return nil to preserve that meaning.
	// Note that if we would explicitly set it to all zeroes then when loading
	// this back it would get a start column of 1.
	if region.StartLine == 0 && region.EndLine == 0 && region.StartColumn == 0 && region.EndColumn == 0 {
		return nil
	}
	return &v210.Region{
		StartLine:   int(region.StartLine),
		EndLine:     int(region.EndLine),
		StartColumn: int(region.StartColumn),
		EndColumn:   int(region.EndColumn),
	}
}

// BuildArtifactLocation creates an artifact location from the given path.
// This effective converts the path to an URI, however care is taken so
// the same URI can be read back into a path returning the same value.
func BuildArtifactLocation(path string) *v210.ArtifactLocation {
	// We might need to escape the path before putting it into the URI.
	// See https://github.com/github/code-scanning/issues/7343 for more details.
	// We try to only do escaping only when needed to make the output as similar
	// to the input as possible.
	// To help test changes to this method one can use the sarif_fuzz_test.go#FuzzEscape test.

	// By default we try to just use the path directly
	uri := path
	parsedPath, err := URIToPath(uri, "")
	if err != nil || parsedPath != path {
		// However if that parse differently then we fully escape everything.
		// Note that we have to escape ':' manually as that is not normally escaped in paths,
		// but our parsing methods will (silently) reject e.g. the string ':' as it is
		// ambiguous with the schema.
		uri = strings.ReplaceAll(url.PathEscape(path), ":", "%3A")
	}
	return &v210.ArtifactLocation{Uri: uri}
}

func groupCodeFlows(c *ts.CodeFlowsDocument) [][][]ts.CodeFlow {
	if c == nil {
		return nil
	}

	codeFlows := c.Document

	output := make([][][]ts.CodeFlow, 0)

	// CodeFlows are in order and do not need to be sorted.
	for _, byCodeFlow := range ts.GroupByCodeFlowIndex(codeFlows) {
		indexed := make([][]ts.CodeFlow, 0, len(byCodeFlow))

		for _, byThreadFlow := range ts.GroupByThreadFlowIndex(byCodeFlow) {
			indexed = append(indexed, byThreadFlow)
		}

		output = append(output, indexed)
	}

	return output
}

func BuildCodeFlows(c *ts.CodeFlowsDocument) []*v210.CodeFlow {
	groups := groupCodeFlows(c)

	codeFlows := make([]*v210.CodeFlow, 0, len(groups))

	for _, byCodeFlow := range groups {
		codeFlow := &v210.CodeFlow{}
		codeFlows = append(codeFlows, codeFlow)
		codeFlow.ThreadFlows = make([]*v210.ThreadFlow, 0, len(byCodeFlow))

		for _, byThreadFlow := range byCodeFlow {
			threadFlow := &v210.ThreadFlow{}
			codeFlow.ThreadFlows = append(codeFlow.ThreadFlows, threadFlow)
			threadFlow.Locations = make([]*v210.ThreadFlowLocation, 0, len(byThreadFlow))

			for _, step := range byThreadFlow {
				threadFlowLocation := &v210.ThreadFlowLocation{}
				threadFlowLocation.Location = &v210.Location{}

				if step.Message != nil {
					threadFlowLocation.Location.Message = &v210.Message{Text: *step.Message}
				}

				physicalLocation := &v210.PhysicalLocation{}
				threadFlowLocation.Location.PhysicalLocation = physicalLocation
				physicalLocation.ArtifactLocation = BuildArtifactLocation(step.FilePath)
				physicalLocation.Region = BuildRegion(step.Region)

				threadFlow.Locations = append(threadFlow.Locations, threadFlowLocation)
			}
		}
	}

	return codeFlows
}

func BuildArtifacts(results []*v210.Result) []*v210.Artifact {
	artifactLocations := make([]*v210.ArtifactLocation, 0)
	for _, r := range results {
		artifactLocations = append(artifactLocations, r.Locations[0].PhysicalLocation.ArtifactLocation)

		for _, cf := range r.CodeFlows {
			for _, tf := range cf.ThreadFlows {
				for _, location := range tf.Locations {
					artifactLocations = append(artifactLocations, location.Location.PhysicalLocation.ArtifactLocation)
				}
			}
		}
	}

	uriToIndex := make(map[string]int)
	artifacts := make([]*v210.Artifact, 0)
	i := 0
	for _, artifactLocation := range artifactLocations {
		index, ok := uriToIndex[artifactLocation.Uri]
		if !ok {
			uriToIndex[artifactLocation.Uri] = i
			index = i
			i++

			artifacts = append(artifacts, &v210.Artifact{Location: artifactLocation})
		}
		artifactLocation.Index = index
	}

	return artifacts
}

func BuildOutdatedSarif(toolName ts.ToolName, category ts.Category) (*v210.SARIF210ForGitHubCodeScanning, error) {
	if toolName == "" {
		return nil, errors.New("toolName is required")
	}
	sarif := NewSarif()
	run := &v210.Run{}

	run.AutomationDetails = &v210.RunAutomationDetails{}
	run.AutomationDetails.Id = category.String() + "/"

	t := &v210.Tool{}
	t.Driver = &v210.ToolComponent{}
	t.Driver.Name = toolName.String()
	run.Tool = t

	sarif.Runs = []*v210.Run{run}
	return sarif, nil
}

func ExtractRules(sarifStr string) []string {
	var rules []string
	var e v210.SARIF210ForGitHubCodeScanning
	err := json.Unmarshal([]byte(sarifStr), &e)
	if err == nil {
		for _, r := range e.Runs {
			for _, ru := range r.Tool.Driver.Rules {
				rules = append(rules, ru.Id)
			}
			for _, e := range r.Tool.Extensions {
				for _, ru := range e.Rules {
					rules = append(rules, ru.Id)
				}
			}
		}
	}
	return rules
}

func buildCodeQLConfigSummary(analysis *ts.Analysis) *v210.CodeqlConfigSummary {
	if analysis.DefaultQueriesDisabled == nil && analysis.AnalysisQuerySuites == nil {
		return nil
	}
	codeqlConfig := &v210.CodeqlConfigSummary{}
	if analysis.DefaultQueriesDisabled != nil {
		codeqlConfig.DisableDefaultQueries = *analysis.DefaultQueriesDisabled
	}
	if analysis.AnalysisQuerySuites != nil {
		codeqlConfig.Queries = make([]*v210.QueriesItems, 0, len(analysis.AnalysisQuerySuites))
		for _, suite := range analysis.AnalysisQuerySuites {
			codeqlConfig.Queries = append(codeqlConfig.Queries, &v210.QueriesItems{
				Type: suite.Type.String(),
				Uses: suite.Uses,
			})
		}
	}
	return codeqlConfig
}
