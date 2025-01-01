package sarif

import (
	_ "embed"
	"sync"

	"golang.org/x/exp/maps"

	v2_1_0 "github.com/github/turboscan/ts/sarif/v2_1_0_turboscan"
	"github.com/pkg/errors"
)

//go:embed ruledata/codeql.sarif
var codeql []byte

// Until the actions queries (https://github.com/github/codeql-actions) are
// included in main codeql repo, we need to embed the help for the queries
// separately.
//
//go:embed ruledata/codeql-actions.sarif
var codeqlActions []byte

// rules that have been deleted, but we want to keep the rulehelp.
//
//go:embed ruledata/codeql-deleted.sarif
var codeqlDeleted []byte

//go:embed ruledata/rubocop.sarif
var rubocop []byte

//go:embed ruledata/eslint.sarif
var eslint []byte

var rules = [][]byte{codeql, codeqlActions, codeqlDeleted, rubocop, eslint}

type RuleMetadataAugmentor interface {
	AugmentDefaultRuleData(run *v2_1_0.Run) error
	DefaultRulesDataByTool(tool string) map[string]*v2_1_0.Rule
	ToolsWithDefaultRuleData() ([]string, error)
}

type NullRuleMetadataAugmentor struct {
}

func (rma *NullRuleMetadataAugmentor) AugmentDefaultRuleData(*v2_1_0.Run) error {
	return nil
}
func (rma *NullRuleMetadataAugmentor) ToolsWithDefaultRuleData() ([]string, error) {
	return []string{}, nil
}
func (rma *NullRuleMetadataAugmentor) DefaultRulesDataByTool(string) (v map[string]*v2_1_0.Rule) {
	return
}

type ruleMetadataAugmentor struct {
	defaultsByIdByTool map[string]map[string]*v2_1_0.Rule
}

var DefaultRuleMetadataAugmentor = sync.OnceValues(func() (RuleMetadataAugmentor, error) {
	// memoize a default augmentor to speed up testing
	return NewRuleMetadataAugmentor(rules)
})

func NewRuleMetadataAugmentor(allRules [][]byte) (RuleMetadataAugmentor, error) {
	// Create a map storing the defaults
	m := make(map[string]map[string]*v2_1_0.Rule)
	for _, d := range allRules {
		err := addDefaultsToMap(d, m)
		if err != nil {
			return nil, err
		}
	}

	return &ruleMetadataAugmentor{
		defaultsByIdByTool: m,
	}, nil
}

func addDefaultsToMap(data []byte, m map[string]map[string]*v2_1_0.Rule) error {
	sarif, err := Decode(data)

	if err != nil {
		return err
	}

	if len(sarif.Runs) != 1 {
		return errors.Errorf("Embedded data must have exactly one run but has %d", len(sarif.Runs))
	}

	dest := m[sarif.Runs[0].Tool.Driver.Name]
	if dest == nil {
		dest = make(map[string]*v2_1_0.Rule)
		m[sarif.Runs[0].Tool.Driver.Name] = dest
	}

	for _, tc := range append(sarif.Runs[0].Tool.Extensions, sarif.Runs[0].Tool.Driver) {
		for _, rule := range tc.Rules {
			_, alreadyExists := dest[rule.Id]
			if alreadyExists {
				return errors.Errorf("Embedded data contains multiple definitions for id '%s'", rule.Id)
			}
			dest[rule.Id] = rule
		}
	}

	return nil
}

// ToolsWithDefaultRuleData reports tools that we have defaults for. Only used by testing
func (r *ruleMetadataAugmentor) ToolsWithDefaultRuleData() ([]string, error) {
	return maps.Keys(r.defaultsByIdByTool), nil
}

// AugmentDefaultRuleData augments the rules lisited in the given run by adding missing metadata
func (r *ruleMetadataAugmentor) AugmentDefaultRuleData(run *v2_1_0.Run) error {

	defaultRuleById, ok := r.defaultsByIdByTool[run.Tool.Driver.Name]
	if !ok {
		return nil
	}

	for _, tc := range append(run.Tool.Extensions, run.Tool.Driver) {
		for _, rule := range tc.Rules {
			if defaultRuleById[rule.Id] != nil {
				augmentRule(rule, defaultRuleById[rule.Id])
			}
		}
	}
	return nil
}

func (r *ruleMetadataAugmentor) DefaultRulesDataByTool(tool string) (v map[string]*v2_1_0.Rule) {
	defaultRuleById, ok := r.defaultsByIdByTool[tool]
	if !ok {
		return
	}
	return defaultRuleById
}

func augmentRule(rule *v2_1_0.Rule, defaultRule *v2_1_0.Rule) {

	if defaultRule == nil {
		return
	}

	// Check important properties match
	if rule.Id != defaultRule.Id {
		return
	}

	// Source missing data from default

	if defaultRule.DefaultConfiguration != nil && defaultRule.DefaultConfiguration.Level != "" {
		if rule.DefaultConfiguration == nil || rule.DefaultConfiguration.Level == "" {
			rule.DefaultConfiguration = defaultRule.DefaultConfiguration
		}
	}

	if isEmpty(rule.FullDescription) {
		rule.FullDescription = defaultRule.FullDescription
	}

	if isEmpty(rule.Help) {
		rule.Help = defaultRule.Help
	}

	if rule.HelpUri == "" {
		rule.HelpUri = defaultRule.HelpUri
	}

	if defaultRule.Properties != nil {
		if rule.Properties == nil {
			rule.Properties = &v2_1_0.ReportingDescriptorPropertyBag{}
		}
		if rule.Properties.Precision == "" {
			rule.Properties.Precision = defaultRule.Properties.Precision
		}
		if rule.Properties.QueryURI == "" {
			rule.Properties.QueryURI = defaultRule.Properties.QueryURI
		}
		if len(rule.Properties.Tags) == 0 {
			rule.Properties.Tags = defaultRule.Properties.Tags
		}

		if rule.Properties.SecuritySeverity == "" {
			rule.Properties.SecuritySeverity = defaultRule.Properties.SecuritySeverity
		}
	}

	if rule.Name == "" {
		rule.Name = defaultRule.Name
	}

	if isEmpty(rule.ShortDescription) {
		rule.ShortDescription = defaultRule.ShortDescription
	}
}

func isEmpty(s *v2_1_0.MultiformatMessageString) bool {
	return s == nil || (s.Markdown == "" && s.Text == "")
}
