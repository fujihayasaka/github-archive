package cocofix

import (
	_ "embed"
	"encoding/json"
)

//go:embed .tool_coverages.json
var content []byte

const (
	CocofixDefaultSuite           string = "default"
	CocofixCopilotCodeReviewSuite string = "ccr"
)

type tool string
type language string
type rule string

type ToolCoverages struct {
	Tools map[tool]map[language]map[rule]Coverage
}

func (tc ToolCoverages) IsSupported(n tool) bool {
	return true
}

func (tc ToolCoverages) FindCoverage(t string, r string) (Coverage, bool) {
	tool, ok := tc.Tools[tool(t)]
	if !ok {
		return Coverage{}, false
	}

	for _, rules := range tool {
		cov, ok := rules[rule(r)]
		if ok {
			return cov, true
		}
	}

	return Coverage{}, false
}

type Coverage struct {
	Suites []string `json:"suites"`
}

func (c Coverage) IsSupported(suite string) bool {
	for _, s := range c.Suites {
		if s == suite {
			return true
		}
	}
	return false
}

func (c Coverage) IsDefaultSuite() bool {
	return c.IsSupported(CocofixDefaultSuite)
}

func (c Coverage) IsCopilotCodeReviewSuite() bool {
	return c.IsSupported(CocofixCopilotCodeReviewSuite)
}

var (
	ToolCoverageMap ToolCoverages
)

func init() {
	err := json.Unmarshal(content, &ToolCoverageMap)
	if err != nil {
		panic(err)
	}
}

func (tc *ToolCoverages) UnmarshalJSON(data []byte) error {
	var raw map[string]map[string]map[string]Coverage
	if err := json.Unmarshal(data, &raw); err != nil {
		return err
	}

	tc.Tools = make(map[tool]map[language]map[rule]Coverage)
	for t, langs := range raw {
		toolKey := tool(t)
		tc.Tools[toolKey] = make(map[language]map[rule]Coverage)
		for l, rules := range langs {
			langKey := language(l)
			tc.Tools[toolKey][langKey] = make(map[rule]Coverage)
			for r, cov := range rules {
				ruleKey := rule(r)
				tc.Tools[toolKey][langKey][ruleKey] = cov
			}
		}
	}

	return nil
}
