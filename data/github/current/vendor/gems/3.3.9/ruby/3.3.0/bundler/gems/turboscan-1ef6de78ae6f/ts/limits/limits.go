// Package limits defines limits to the number of occurrences of certain operations.
package limits

import (
	"fmt"

	"github.com/github/turboscan/ts"
)

const AllRepos = 0

// Table stores the values for all limits
type Table struct {
	RunsPerSarifLimit                int
	RulesPerRunLimit                 int
	ResPerRunLimit                   int
	ToolExtensionsPerRunLimit        int
	LocPerResLimit                   int
	StepsPerResLimit                 int
	MetricsPerRunLimit               int
	TagsPerRuleLimit                 int
	SuggestedFixesLimit              int // The maximum number of fixes that we attempt generate for a single analysis
	SuggestedFixesDownloadFilesLimit int
	NotExtractedFilesMessagesLimit   int // Maximum number of diagnostic (warning or error) messages saved per analysis
	ExtractedFilesLimit              int
	NotExtractedFilesLimit           int
	FixesCopiedLimit                 int // The maximum number of fixes that we copy from the baseline analysis to the new analysis during processing
	LogicalAlertLimit                int // Maximum number of logical alerts for a repository before we complain at them
}

type LimitError struct {
	Name               string
	RuleSarifIds       []string
	AlertCount         int
	Dropped            int
	Max                int
	Total              int
	AnalysisMessageKey string
}

func (le LimitError) IsRecoverable() bool {
	return true
}

func (le LimitError) Error() string {
	return fmt.Sprintf("%d %s were ignored", le.Dropped, le.Name)
}

// LimitsDefault returns the default limits table
func LimitsDefault() Table {
	return Table{
		RunsPerSarifLimit:                20,
		RulesPerRunLimit:                 5000,
		ResPerRunLimit:                   5000,
		ToolExtensionsPerRunLimit:        100,
		LocPerResLimit:                   100,
		StepsPerResLimit:                 1000,
		MetricsPerRunLimit:               5000,
		TagsPerRuleLimit:                 10,
		FixesCopiedLimit:                 5000,
		SuggestedFixesLimit:              20,
		SuggestedFixesDownloadFilesLimit: 200,
		NotExtractedFilesMessagesLimit:   5000,
		ExtractedFilesLimit:              1_500_000,
		NotExtractedFilesLimit:           1_000_000,
		LogicalAlertLimit:                500_000,
	}
}

// LimitsHuge returns extended limits for big repos
// with up to to 10000 results/rules
func LimitsHuge() Table {
	t := LimitsDefault()
	t.ResPerRunLimit = 10000
	t.RulesPerRunLimit = 10000
	return t
}

// LimitsInternal is used for reading internally written results:
//
//	It should allow any size that we have allowed in the past.
//	It should not be used for externally provided data.
func LimitsInternal() Table {
	t := LimitsDefault()
	t.ResPerRunLimit = 10000
	t.RulesPerRunLimit = 10000
	t.StepsPerResLimit = 5000
	t.TagsPerRuleLimit = 500
	t.ToolExtensionsPerRunLimit = 1000
	return t
}

// LimitSelector is responsible for chosing the correct limits to apply.
type LimitSelector struct {
	limitsForRepo    map[ts.RepositoryEID]Table
	disableHardLimit bool
}

func TestLimitSelector() *LimitSelector {
	return NewLimitSelector(nil, false)
}

func NewLimitSelector(os map[ts.RepositoryEID]Table, disableHardLimit bool) *LimitSelector {
	ls := &LimitSelector{
		limitsForRepo: map[ts.RepositoryEID]Table{
			AllRepos: LimitsDefault(),
		},
		disableHardLimit: disableHardLimit,
	}
	for k, v := range os {
		ls.limitsForRepo[k] = v
	}
	return ls
}

// GetLimits gets the limits for a particular repository, with repository-specific overrides applied.
func (ls LimitSelector) GetLimits(r ts.RepositoryEID) Table {
	if t, ok := ls.limitsForRepo[r]; ok {
		return t
	}
	t := ls.limitsForRepo[AllRepos]
	return t
}

// GetHardLimits checks whether the hard limits are enabled, and if so, returns the SARIF limit values which are used
// to reject the SARIF's upload if exceeded for a particular repository, with repository-specific overrides applied.
func (ls LimitSelector) GetHardLimits(r ts.RepositoryEID) (Table, bool) {
	if !ls.HardLimitEnabled() {
		return Table{}, false
	}

	repoLimits := ls.GetLimits(r)
	return Table{
		RunsPerSarifLimit:         repoLimits.RunsPerSarifLimit,
		RulesPerRunLimit:          repoLimits.RulesPerRunLimit * 5,
		ResPerRunLimit:            repoLimits.ResPerRunLimit * 5,
		ToolExtensionsPerRunLimit: repoLimits.ToolExtensionsPerRunLimit,
		LocPerResLimit:            repoLimits.LocPerResLimit * 10,
		StepsPerResLimit:          repoLimits.StepsPerResLimit * 10,
		TagsPerRuleLimit:          repoLimits.TagsPerRuleLimit * 2,
		LogicalAlertLimit:         repoLimits.LogicalAlertLimit * 2,
	}, true
}

// HardLimitEnabled returns whether the SARIF hard limit should be enforced
func (ls LimitSelector) HardLimitEnabled() bool {
	return !ls.disableHardLimit
}

func (t Table) WithFixesCopiedLimit(fixesCopiedLimit int) Table {
	t.FixesCopiedLimit = fixesCopiedLimit
	return t
}
