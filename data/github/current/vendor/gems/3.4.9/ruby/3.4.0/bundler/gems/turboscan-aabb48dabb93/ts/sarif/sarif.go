// Package sarif provides tools to operate on a SARIF structure.
//
// Most functions in this file are focused on providing porcelain on
// the auto-generated SARIF structure, with a particular focus on
// capturing the semantics of the specification:
// http://docs.oasis-open.org/sarif/sarif/v2.1.0/sarif-v2.1.0.html
package sarif

import (
	"context"
	"net/url"
	"sort"
	"strconv"
	"strings"

	"github.com/github/turboscan/ts/appctx"

	"github.com/aws/smithy-go/ptr"
	"golang.org/x/exp/maps"
	"golang.org/x/mod/semver"

	"github.com/pkg/errors"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/limits"
	v2_1_0 "github.com/github/turboscan/ts/sarif/v2_1_0_turboscan"
	"github.com/github/turboscan/ts/transforms"
)

const (
	// CodeqlDiagnosticTelemetryVersion is the first version of the CodeQL CLI that supports
	// diagnostic telemetry.
	CodeqlDiagnosticTelemetryVersion = "2.14.2"
)

// Suppressed returns true if the result is suppressed.
func Suppressed(result *v2_1_0.Result) (suppressed bool, err error) {
	// Suppression is described in 3.27.23 and 3.35
	if result.Suppressions == nil {
		// If the field is not available, or explicitly null
		// then the result is not suppressed
		return false, nil
	}

	for _, sup := range result.Suppressions {
		// TODO: the `state` field is actually called `status` in the spec
		// so we might need to update the parser later to handle that
		// for now we implement using the `state` field and rely
		// on the compiler when the parser is updated
		if sup.State == nil {
			// A suppression without an explicit comment
			// is considered accepted, meaning the result should be suppressed.
			return true, nil
		}
		// The state is a general interface (but should be a string according to the spec)
		// so we check it here
		switch sup.State {
		case "accepted":
			// An accepted suppression
			return true, nil
		case "underReview", "rejected":
			// Suppressions that are not accepted
		default:
			// Suppression status is not considered sensitive data
			return false, errors.Errorf("suppression status '%v' not recognized", sup.State)
		}
	}

	// No accepted suppression (or no at all)
	// then the result is not suppressed
	return false, nil
}

// RuleFromResult is just syntactic sugar for RuleLookup
func RuleFromResult(run *v2_1_0.Run, result *v2_1_0.Result) (*v2_1_0.Rule, v2_1_0.ToolComponentIndicator, error) {
	return run.RuleLookup(result.RuleId, result.RuleIndex, result.Rule)
}

// RuleAndToolComponentIndicator tracks a rule and which tool or extension it came from.
type RuleAndToolComponentIndicator struct {
	Rule                   *v2_1_0.Rule
	ToolComponentIndicator v2_1_0.ToolComponentIndicator
}

// GetRules returns the rules from all tools and extensions in this run.
func GetRules(run *v2_1_0.Run) (map[string]RuleAndToolComponentIndicator, error) {
	// A map to hold the rules. Note that if we're encountering several
	// definitions of a rule with a certain id, either within a single tool
	// component or in different ones, the last occurrence 'wins' and we'll use
	// its metadata definition only. We might want to reconsider this in the
	// future.
	sarifRules := map[string]RuleAndToolComponentIndicator{}
	// We iterate first over the results, as we might hit the limit of rules
	// allowed for a run, we want to ensure that we consider all rules used in
	// the results (up to the limit) - This is outdated, as we do not enforce
	// a limit here. We probably should, but rely only on the SARIF hard limit.
	for _, result := range run.Results {
		sarifRule, tcInd, err := RuleFromResult(run, result)
		if err != nil {
			return nil, err
		}

		sarifRules[sarifRule.Id] = RuleAndToolComponentIndicator{Rule: sarifRule, ToolComponentIndicator: tcInd}
	}

	// We then consider all Rules that are defined for the Tool Driver. In most
	// cases, these will overlap with the ones used in the results, but if no
	// result for a rule exists, we still want to know that the rule was
	// evaluated.
	for _, sarifRule := range run.Tool.Driver.Rules {
		sarifRules[sarifRule.Id] = RuleAndToolComponentIndicator{Rule: sarifRule, ToolComponentIndicator: v2_1_0.ToolComponentDriver}
	}

	// We then consider all Rules that are defined for the Tool Extensions
	for i, ext := range run.Tool.Extensions {
		for _, sarifRule := range ext.Rules {
			sarifRules[sarifRule.Id] = RuleAndToolComponentIndicator{Rule: sarifRule, ToolComponentIndicator: v2_1_0.ToolComponentIndicator(i)}
		}
	}

	return sarifRules, nil
}

// NewTool creates a tool from name and guid, optionally generating a stable internal guid if one is not provided.
func NewTool(guid string, name ts.ToolName) *ts.Tool {
	// if the tool is still reporting the old name (or was never renamed) rename the tool with the preferred name
	if canonicalName, ok := ts.CanonicalToolRenames[name]; ok {
		name = canonicalName
	}
	if guid != "" {
		return &ts.Tool{GUID: guid, CanonicalName: name}
	}
	return ts.ToolFromCanonicalName(name)
}

// memoize stores a single pointer for each unique value of type T.
type memoize[T comparable] map[T]*T

// Get returns the distinct pointer for the value v, storing it if it not present.
func (d memoize[T]) Get(v *T) *T {
	// if a pointer already exists for this value return it
	if ptr, ok := d[*v]; ok {
		return ptr
	}
	// otherwise store the pointer and give it back
	d[*v] = v
	return v
}

func toolVersionFromToolComponent(tc *v2_1_0.ToolComponent, tools memoize[ts.Tool], toolVersions memoize[ts.ToolVersion]) *ts.ToolVersion {
	var isCodeQLModelPack bool
	if tc.Properties != nil && tc.Properties.AdditionalProperties != nil {
		isCodeQLModelPackProperty, ok := tc.Properties.AdditionalProperties["isCodeQLModelPack"]
		if ok {
			// Intentionally ignore `ok` here, as we want to set the value to false if the property is not present
			isCodeQLModelPack, _ = isCodeQLModelPackProperty.(bool)
		}
	}

	name := ts.ToToolName(tc.Name)
	return toolVersions.Get(&ts.ToolVersion{
		Name:              name,
		FullName:          tc.FullName,
		Version:           tc.Version,
		SemanticVersion:   tc.SemanticVersion,
		IsCodeQLModelPack: isCodeQLModelPack,
		Tool:              tools.Get(NewTool(tc.Guid, name)),
	})
}

func ToolVersionsFromSarifRun(run *v2_1_0.Run) (driver *ts.ToolVersion, extensions []*ts.ToolVersion, err error) {
	if run == nil || run.Tool == nil || run.Tool.Driver == nil {
		err = errors.New("driver missing from run")
		return
	}

	var tools = make(memoize[ts.Tool])
	var toolVersions = make(memoize[ts.ToolVersion])

	driver = toolVersionFromToolComponent(run.Tool.Driver, tools, toolVersions)

	extensions = make([]*ts.ToolVersion, 0, len(run.Tool.Extensions))

	for _, extension := range run.Tool.Extensions {
		extensions = append(extensions, toolVersionFromToolComponent(extension, tools, toolVersions))
	}

	return
}

// ConvertRules transforms a set of sarif rules into their ts.Rule counterparts.
func ConvertRules(ctx context.Context, sarifRules map[string]RuleAndToolComponentIndicator, driver *ts.ToolVersion, extensions []*ts.ToolVersion, tagsPerRuleLimit int) (map[string]*ts.Rule, *limits.LimitError, error) {
	// We can now process the updates in the DB.
	rulesBySarifIdentifier := make(map[string]*ts.Rule, len(sarifRules))
	ruleIdentifiersAboveLimit := map[string]int{}
	for _, sarifRule := range sarifRules {
		rule, tagsAboveLimit, err := RuleFromSarifRule(sarifRule.Rule, driver.Tool, tagsPerRuleLimit)
		if err != nil {
			return nil, nil, err
		}

		if tagsAboveLimit > 0 {
			ruleIdentifiersAboveLimit[rule.SarifIdentifier] += tagsAboveLimit
		}

		// Set the defining driver version
		switch {
		case sarifRule.ToolComponentIndicator.IsDriver():
			rule.DefiningToolVersionID = driver.ID
		case sarifRule.ToolComponentIndicator.IsExtension():
			rule.DefiningToolVersionID = extensions[sarifRule.ToolComponentIndicator].ID
		default:
			rule.DefiningToolVersionID = ts.ToolVersionUnspecified
		}

		rulesBySarifIdentifier[rule.SarifIdentifier] = rule
	}

	var limitErr *limits.LimitError
	if len(ruleIdentifiersAboveLimit) > 0 {
		ruleSarifIds := maps.Keys(ruleIdentifiersAboveLimit)
		sort.Strings(ruleSarifIds)
		var tagsAboveLimit int
		for _, n := range maps.Values(ruleIdentifiersAboveLimit) {
			tagsAboveLimit += n
		}
		limitErr = &limits.LimitError{
			Name:               "ruleTags",
			RuleSarifIds:       ruleSarifIds,
			Dropped:            tagsAboveLimit,
			Max:                tagsPerRuleLimit,
			Total:              tagsPerRuleLimit + tagsAboveLimit,
			AnalysisMessageKey: string(ts.MessageSarifSoftLimitTagsPerRule),
		}
		appctx.Logger(ctx).Info("Soft limit applied to rule tags", kvp.Int("gh.turboscan.ignored", tagsAboveLimit), kvp.Strings("gh.turboscan.rule_sarif_identifiers", ruleSarifIds))
	}

	return rulesBySarifIdentifier, limitErr, nil
}

var ErrSarifIdentifierTooLong = errors.New("sarif identifier exceeds maximum length of 255 characters")

// RuleFromSarifRule converts a SARIF Rule object into an internal Rule object
//
// The function defines the mapping between SARIF fields and internal
// Rule fields, including applying some defaults and restrictions.
// Returns the internal Rule object, and the number of removed tags based on the tagsPerRuleLimit restriction.
func RuleFromSarifRule(sarifRule *v2_1_0.Rule, tool *ts.Tool, tagsPerRuleLimit int) (*ts.Rule, int, error) {
	rule := &ts.Rule{
		Tool:   tool,
		ToolID: tool.ID,
		Tags:   []ts.RuleTag{},
	}
	if len(sarifRule.Id) > 255 {
		return rule, 0, ErrSarifIdentifierTooLong
	}
	rule.SarifIdentifier = sarifRule.Id
	rule.Name = ts.Truncate(sarifRule.Name, 255)
	rule.HelpURI = ts.Truncate(sarifRule.HelpUri, 1024)
	// NOTE: Only consider the plain-text version of these fields
	if sarifRule.ShortDescription != nil {
		rule.ShortDescription = ts.Truncate(sarifRule.ShortDescription.Text, 1024)
	}
	if sarifRule.FullDescription != nil {
		rule.FullDescription = ts.Truncate(sarifRule.FullDescription.Text, 1024)
	}
	if sarifRule.Help != nil {
		if sarifRule.Help.Markdown != "" {
			rule.Help = ts.Truncate(sarifRule.Help.Markdown, 64*1024)
		} else {
			rule.Help = ts.Truncate(sarifRule.Help.Text, 64*1024)
		}
	}
	rule.SeverityLevel = ts.SeverityLevelWarning
	if sarifRule.DefaultConfiguration != nil && sarifRule.DefaultConfiguration.Level != "" {
		sl, err := ts.NewSeverityLevel(sarifRule.DefaultConfiguration.Level)
		if err != nil {
			return rule, 0, err
		}
		rule.SeverityLevel = sl
	}

	var tagsAboveLimit int
	if sarifRule.Properties != nil {
		rule.SetPrecision(sarifRule.Properties.Precision)

		if sarifRule.Properties.Tags != nil {
			for idx := range sarifRule.Properties.Tags {
				sarifRule.Properties.Tags[idx] = ts.Truncate(sarifRule.Properties.Tags[idx], 255)
			}
			// set the tags while removing duplicates
			rule.SetTags(sarifRule.Properties.Tags)

			// remove tags so that its number remains within limit
			tagsAboveLimit = len(rule.Tags) - tagsPerRuleLimit
			if tagsAboveLimit > 0 {
				ruleTags, err := rule.GetTags()
				if err != nil {
					return rule, 0, err
				}
				sort.Strings(ruleTags)
				rule.SetTags(ruleTags[:tagsPerRuleLimit])
			}
		}

		if sarifRule.Properties.QueryURI != "" {
			rule.QueryURI = sarifRule.Properties.QueryURI
		}

		if sarifRule.Properties.SecuritySeverity != "" {
			f, err := strconv.ParseFloat(sarifRule.Properties.SecuritySeverity, 64)
			if err != nil {
				return rule, 0, errors.Errorf("invalid security severity value, is not a number: %s",
					sarifRule.Properties.SecuritySeverity)
			}

			rule.SecuritySeverity = &f
		}
	}

	err := rule.UpdateHash()
	return rule, tagsAboveLimit, err
}

// GetAutomationID extracts the automation details ID from the run, handling the
// case where the automation details object is nil by returning the empty
// string.
func GetAutomationID(run *v2_1_0.Run) string {
	if run.AutomationDetails == nil {
		return ""
	}
	return run.AutomationDetails.Id
}

// URIToPath returns a file path from the given URI string and
// checkout URI string.
// SARIF locations are URIs, not file paths. To display alerts in the
// correct files, we need to decode these URIs and turn absolute paths
// into paths relative to the root of the repository.
// NOTE: the filepaths returned from this are used in the stable IDs of
// the alerts, so a change here could mean that fresh logical alerts
// gets created - so care should be taken.
func URIToPath(sarifURIString string, checkoutURIString ts.CheckoutURI) (string, error) {
	sarifURI, err := url.Parse(sarifURIString)
	if err != nil {
		return "", errors.Wrap(err, "an invalid URI was provided as a SARIF location")
	}

	// If the URI has no scheme it is already relative (hopefully to the checkout root).
	switch {
	case sarifURI.Scheme == "":
		return sarifURI.Path, nil
	case checkoutURIString == "":
		if sarifURI.Scheme == "file" {
			// If no checkout URI is provided, we don't perform any transformations on absolute URIs.
			return sarifURIString, nil
		}
		return "", errors.Errorf("unrecognized SARIF location URI scheme %q", sarifURI.Scheme)
	default:

		checkoutURI, err := url.Parse(checkoutURIString.String())
		if err != nil {
			return "", errors.Wrap(err, "an invalid URI was provided as the checkout location")
		}
		if sarifURI.Scheme != checkoutURI.Scheme {
			return "", errors.Errorf("SARIF URI scheme %q did not match the checkout URI scheme %q", sarifURI.Scheme, checkoutURI.Scheme)
		}
		checkoutPath := checkoutURI.Path
		if !strings.HasSuffix(checkoutPath, "/") {
			checkoutPath += "/"
		}
		sarifPath := sarifURI.Path
		if !strings.HasSuffix(sarifPath, "/") {
			sarifPath += "/"
		}
		if !strings.HasPrefix(sarifPath, checkoutPath) {
			// The file may be outside the root of the checkout. In this case we perform no transformation.
			return sarifURIString, nil
		}
		return strings.TrimSuffix(sarifPath[len(checkoutPath):], "/"), nil
	}
}

func ConvertSarifNotificationLocationsToAnalysisMessageLocations(locations []*v2_1_0.Location) []*ts.AnalysisMessageLocation {
	var analysisMessageLocations []*ts.AnalysisMessageLocation
	var startLine, startColumn, endLine, endColumn int
	var uri string

	analysisMessageLocations = transforms.Map(locations, func(location *v2_1_0.Location) *ts.AnalysisMessageLocation {
		if location.PhysicalLocation.Region != nil {
			startLine = location.PhysicalLocation.Region.StartLine
			startColumn = location.PhysicalLocation.Region.StartColumn
			endLine = location.PhysicalLocation.Region.EndLine
			endColumn = location.PhysicalLocation.Region.EndColumn
		}

		if location.PhysicalLocation.ArtifactLocation != nil {
			uri = location.PhysicalLocation.ArtifactLocation.Uri
		}

		return &ts.AnalysisMessageLocation{
			FilePath:    uri,
			StartLine:   startLine,
			StartColumn: startColumn,
			EndLine:     endLine,
			EndColumn:   endColumn,
		}
	})

	return analysisMessageLocations
}

func toAnalysisQuerySuiteType(v string) ts.AnalysisQuerySuiteType {
	switch v {
	case "localQuery":
		return ts.AnalysisQuerySuiteTypeLocalQuery
	case "builtinSuite":
		return ts.AnalysisQuerySuiteTypeBuiltinSuite
	case "externalRepo":
		return ts.AnalysisQuerySuiteTypeExternalRepo
	default:
		return ts.AnalysisQuerySuiteTypeUnknown
	}
}

func toAnalysisQuerySuite(item *v2_1_0.QueriesItems) (*ts.AnalysisQuerySuite, bool) {
	if item == nil {
		return nil, false
	}
	return &ts.AnalysisQuerySuite{
		Type: toAnalysisQuerySuiteType(item.Type),
		Uses: ts.Truncate(item.Uses, 1024),
	}, true
}

func GetCodeQLConfig(run *v2_1_0.Run) (*bool, []*ts.AnalysisQuerySuite) {
	if run == nil || run.Properties == nil || run.Properties.CodeqlConfigSummary == nil {
		return nil, nil
	}
	return ptr.Bool(run.Properties.CodeqlConfigSummary.DisableDefaultQueries), transforms.FilterMap(run.Properties.CodeqlConfigSummary.Queries, toAnalysisQuerySuite)
}

// FindRuleSarifIds returns the sarif ids of all rules for which the given predicate returns true
func FindRuleSarifIds(s *v2_1_0.SARIF, p func(*v2_1_0.Rule) bool) []string {
	ruleSarifIds := make(map[string]bool)

	for _, r := range s.Runs {
		if r.Tool != nil && r.Tool.Driver != nil {
			for _, rule := range r.Tool.Driver.Rules {
				if rule != nil && p(rule) {
					ruleSarifIds[rule.Id] = true
				}
			}
			for _, ext := range r.Tool.Extensions {
				for _, rule := range ext.Rules {
					if rule != nil && p(rule) {
						ruleSarifIds[rule.Id] = true
					}
				}
			}
		}
	}

	return maps.Keys(ruleSarifIds)
}

// FindRuleSarifIdsForResults returns the sarif ids of all rules for whose results the given predicate returns true
// and the total count of those results.
func FindRuleSarifIdsForResults(ctx context.Context, s *v2_1_0.SARIF, p func(*v2_1_0.Result) bool) ([]string, int) {
	ruleSarifIds := make(map[string]bool)
	resultCount := 0

	for _, r := range s.Runs {
		for _, result := range r.Results {
			if result != nil && p(result) {
				rule, _, err := RuleFromResult(r, result)
				if err != nil {
					appctx.Logger(ctx).WithError(err).Error("could not find rule name from result")
				}
				ruleSarifIds[rule.Id] = true
				resultCount++
			}
		}
	}

	return maps.Keys(ruleSarifIds), resultCount
}

type NotificationWithHierarchy struct {
	Notification        *v2_1_0.Notification
	ReportingDescriptor *v2_1_0.ReportingDescriptor
	ToolComponent       *v2_1_0.ToolComponent
	Run                 *v2_1_0.Run
}

func GetCodeqlTelemetryDiagnostics(ctx context.Context, sarif *v2_1_0.SARIF) ([]*NotificationWithHierarchy, error) {
	result := []*NotificationWithHierarchy{}

	for _, run := range sarif.Runs {
		// Skip runs that are not from CodeQL
		if run.Tool == nil || run.Tool.Driver == nil || run.Tool.Driver.Name != "CodeQL" {
			appctx.Logger(ctx).Debug("Skipping run that is not from CodeQL")
			continue
		}

		// Skip runs that do not support diagnostic telemetry
		if !isVersionValid(run.Tool.Driver.SemanticVersion) {
			appctx.Logger(ctx).Warn(
				"Skipping run with invalid semantic version",
				kvp.String("gh.turboscan.codeql_telemetry.semantic_version", run.Tool.Driver.SemanticVersion),
			)
			continue
		}

		if !isVersionAtLeast(run.Tool.Driver.SemanticVersion, CodeqlDiagnosticTelemetryVersion) {
			appctx.Logger(ctx).Debug(
				"Skipping run with CodeQL version that does not support diagnostic telemetry",
				kvp.String("gh.turboscan.codeql_telemetry.semantic_version", run.Tool.Driver.SemanticVersion),
			)
			continue
		}

		// Skip runs that do not have any invocations
		if run.Invocations == nil {
			continue
		}

		// Extract the tool execution notifications in each invocation
		for _, invocation := range run.Invocations {
			if invocation.ToolExecutionNotifications == nil {
				continue
			}

			for _, notification := range invocation.ToolExecutionNotifications {
				if notification.Properties == nil || notification.Properties.Visibility == nil ||
					!notification.Properties.Visibility.Telemetry {
					continue
				}

				toolComponent, reportingDescriptor, err := run.LookupNotification(notification)
				if err != nil {
					return nil, errors.Wrap(err, "could not find reporting descriptor for notification")
				}
				result = append(result, &NotificationWithHierarchy{
					Notification:        notification,
					ReportingDescriptor: reportingDescriptor,
					ToolComponent:       toolComponent,
					Run:                 run,
				})
			}

		}
	}

	return result, nil
}

type MetricResultWithHierarchy struct {
	MetricResult *v2_1_0.MetricResult
	Rule         *v2_1_0.ReportingDescriptor
	Run          *v2_1_0.Run
}

func GetCodeqlMetricResults(sarif *v2_1_0.SARIF, l log.Logger) ([]*MetricResultWithHierarchy, error) {
	result := []*MetricResultWithHierarchy{}

	for _, run := range sarif.Runs {
		// Skip runs that are not from CodeQL
		if run.Tool == nil || run.Tool.Driver == nil || run.Tool.Driver.Name != "CodeQL" {
			l.Debug("Skipping run that is not from CodeQL")
			continue
		}

		if run.Properties == nil || run.Properties.MetricResults == nil {
			continue
		}

		for _, metricResult := range run.Properties.MetricResults {
			if metricResult.Rule == nil {
				return nil, errors.New("metric result is missing a reportingDescriptorReference")
			}
			rule, _, err := run.RuleLookup("", -1, metricResult.Rule)
			if err != nil {
				return nil, errors.Wrap(err, "could not find rule for metric result")
			}
			result = append(result, &MetricResultWithHierarchy{
				MetricResult: metricResult,
				Rule:         rule,
				Run:          run,
			})
		}
	}

	return result, nil
}

func isVersionValid(version string) bool {
	// The semver package requires the "v" prefix, but semantic versions that follow the semver.org
	// spec do not start with "v" (https://semver.org/#is-v123-a-semantic-version).
	return semver.IsValid("v" + version)
}

func isVersionAtLeast(version string, minVersion string) bool {
	// The semver package requires the "v" prefix, but semantic versions that follow the semver.org
	// spec do not start with "v" (https://semver.org/#is-v123-a-semantic-version).
	return semver.Compare("v"+version, "v"+minVersion) >= 0
}
