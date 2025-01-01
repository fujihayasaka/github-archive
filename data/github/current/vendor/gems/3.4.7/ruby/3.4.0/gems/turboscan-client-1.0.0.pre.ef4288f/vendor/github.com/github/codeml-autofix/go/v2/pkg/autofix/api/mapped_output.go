/*
These types are used to represent the final fix output of a suggested fix alert to match the Turboscan
API. https://github.com/github/turboscan/blob/main/ts/suggested_fix_generator.go#L86
*/
package api

// SuggestedFix represents a generated fix suggestion.
type SuggestedFix struct {
	RepositoryID       string
	Description        string
	AiVersion          string // The version of the AI model used to generate the fix
	AiModel            string // The name of the AI model used to generate the fix
	DependencyMetadata []SuggestedFixDependency
	Files              []*SuggestedFixFile
}

// SuggestedFixFile contains diff information for a single changed file in a suggested fix.
type SuggestedFixFile struct {
	FilePath     string
	DiffContent  []byte
	FileChecksum string
	FilePathHash []byte
}

// SuggestedFixDependency captures metadata for a dependency introduced or referenced by the fix.
type SuggestedFixDependency struct {
	Name        string
	Version     string
	Description string
	Url         string
	Ecosystem   string
	IsMalicious bool
	Advisories  []SuggestedFixAdvisory
}

// SuggestedFixAdvisorySeverity enumerates severities for dependency advisories.
type SuggestedFixAdvisorySeverity string

const (
	SuggestedFixAdvisorySeverityUnknown  SuggestedFixAdvisorySeverity = "unknown"
	SuggestedFixAdvisorySeverityLow      SuggestedFixAdvisorySeverity = "low"
	SuggestedFixAdvisorySeverityMedium   SuggestedFixAdvisorySeverity = "medium"
	SuggestedFixAdvisorySeverityHigh     SuggestedFixAdvisorySeverity = "high"
	SuggestedFixAdvisorySeverityCritical SuggestedFixAdvisorySeverity = "critical"
)

// SuggestedFixAdvisory summarizes a security advisory attached to a SuggestedFixDependency.
type SuggestedFixAdvisory struct {
	Id          string
	HtmlUrl     string
	Summary     string
	Description string
	Severity    SuggestedFixAdvisorySeverity
}
