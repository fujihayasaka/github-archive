// Package cocofix defines cocofix types, parser and mapping with alerts
package cocofix

type CocofixResponse []Output

type Output struct {
	CoCoFixVersion string    `json:"cocofixVersion"`
	Alert          respAlert `json:"alert,omitempty"`
	Outcome        Outcome   `json:"outcome"`
}

type respAlert struct {
	Message  string   `json:"message"`
	RuleId   string   `json:"ruleId"`
	Location Location `json:"location"`
}

type OutcomeSeverity string

const (
	OutcomeSeverity_LOW      OutcomeSeverity = "low"
	OutcomeSeverity_HIGH     OutcomeSeverity = "high"
	OutcomeSeverity_CRITICAL OutcomeSeverity = "critical"
)

type Outcome struct {
	// kind: fix|error
	Kind string `json:"kind"`
	// fix suggestion
	Diffs      []Diff     `json:"diffs,omitempty"`
	Assessment Assessment `json:"assessment,omitempty"`
	Details    Details    `json:"details,omitempty"`
	// in case of error
	Error       string          `json:"error,omitempty"`
	Description string          `json:"description,omitempty"`
	Transient   bool            `json:"transient,omitempty"`
	Severity    OutcomeSeverity `json:"severity,omitempty"`
}

type Diff struct {
	Path string `json:"path,omitempty"`
	Diff string `json:"diff,omitempty"`
}

type Rule struct {
	ID string `json:"id"`
}

type Location struct {
	Path        string `json:"path"`
	StartLine   int    `json:"startLine"`
	StartColumn int    `json:"startColumn"`
	EndLine     int    `json:"endLine"`
	EndColumn   int    `json:"endColumn"`
}

type Assessment struct {
	Outcome  string    `json:"outcome,omitempty"`
	Problems []Problem `json:"problems,omitempty"`
}

type ProblemKind string

const (
	ProblemKind_NO_CODE_CHANGES    ProblemKind = "no code changes"
	ProblemKind_SYNTAX_ERROR       ProblemKind = "syntax error"
	ProblemKind_SEMANTIC_ERROR     ProblemKind = "semantic error"
	ProblemKind_MISSING_DEPENDENCY ProblemKind = "missing dependency"
)

type Problem struct {
	Kind        ProblemKind `json:"kind"`
	Description string      `json:"description"`
}

type Details struct {
	FixDescription     string               `json:"fixDescription,omitempty"`
	DependencyMetadata []DependencyMetadata `json:"dependencyMetadata,omitempty"`
}

type DependencyMetadata struct {
	Name        string     `json:"name"`
	Version     string     `json:"version"`
	Ecosystem   string     `json:"ecosystem"`
	Description string     `json:"description,omitempty"`
	Url         string     `json:"url,omitempty"`
	IsMalicious bool       `json:"isMalicious,omitempty"`
	Advisories  []Advisory `json:"advisories,omitempty"`
}

type Advisory struct {
	Id          string `json:"ghsa_id"`
	HtmlUrl     string `json:"html_url"`
	Summmary    string `json:"summary"`
	Description string `json:"description,omitempty"`
	Severity    string `json:"severity"`
}
