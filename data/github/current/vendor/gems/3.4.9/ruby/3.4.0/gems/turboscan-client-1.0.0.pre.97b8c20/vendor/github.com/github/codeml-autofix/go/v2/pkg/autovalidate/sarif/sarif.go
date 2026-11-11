// Package sarif provides utilities for parsing and processing Static Analysis Results
// Interchange Format (SARIF) logs, including filtering alerts and validation functions.
package sarif

import (
	"encoding/json"
	"strings"

	"github.com/github/codeml-autofix/go/v2/pkg/autovalidate/diff"
)

// Log represents the structure of a SARIF log.
type Log struct {
	Version string `json:"version"`
	Schema  string `json:"$schema"`
	Runs    []Run  `json:"runs"`
}

// Run represents a single run in a SARIF report.
type Run struct {
	Tool      Tool       `json:"tool"`
	Artifacts []Artifact `json:"artifacts"`
	Results   []Result   `json:"results"`
}

// Tool represents the analysis tool information in a SARIF report.
type Tool struct {
	Driver Driver `json:"driver"`
}

// Driver represents the tool driver information in a SARIF report.
type Driver struct {
	Name           string `json:"name"`
	InformationURI string `json:"informationUri"`
	Rules          []Rule `json:"rules"`
	Version        string `json:"version"`
}

// Rule represents a rule definition in a SARIF report.
type Rule struct {
	ID               string                 `json:"id"`
	HelpURI          string                 `json:"helpUri"`
	Properties       map[string]interface{} `json:"properties"`
	ShortDescription ShortDescription       `json:"shortDescription"`
}

// ShortDescription represents a short description in SARIF.
type ShortDescription struct {
	Text string `json:"text"`
}

// Artifact represents an artifact (file) in a SARIF report.
type Artifact struct {
	Location Location `json:"location"`
}

// Location represents a file location in SARIF.
type Location struct {
	URI string `json:"uri"`
}

// Result represents a single analysis result in SARIF.
type Result struct {
	Level     string    `json:"level"`
	Message   Message   `json:"message"`
	Locations []LocWrap `json:"locations"`
	RuleID    string    `json:"ruleId"`
	RuleIndex int       `json:"ruleIndex"`
}

// Message represents a message in SARIF.
type Message struct {
	Text string `json:"text"`
}

// LocWrap wraps a physical location in SARIF.
type LocWrap struct {
	PhysicalLocation PhysicalLocation `json:"physicalLocation"`
}

// PhysicalLocation represents a physical location in source code.
type PhysicalLocation struct {
	ArtifactLocation ArtifactLocation `json:"artifactLocation"`
	Region           Region           `json:"region"`
}

// ArtifactLocation represents the location of an artifact (file).
type ArtifactLocation struct {
	URI   string `json:"uri"`
	Index int    `json:"index"`
}

// Region represents a region of source code in SARIF.
type Region struct {
	StartLine   int `json:"startLine"`
	StartColumn int `json:"startColumn"`
	EndLine     int `json:"endLine"`
	EndColumn   int `json:"endColumn"`
}

// Alert represents a linter alert extracted and filtered from SARIF results.
type Alert struct {
	RuleID    string
	Message   string
	FilePath  string
	StartLine int
	EndLine   int
}

// NewLog parses a SARIF log from data.
func NewLog(data []byte) (*Log, error) {
	var sarifLog Log
	if err := json.Unmarshal(data, &sarifLog); err != nil {
		return nil, err
	}

	return &sarifLog, nil
}

// HasFixIntroducedNewAlerts checks if the fix has introduced new alerts or removed existing ones for the given ruleID.
func HasFixIntroducedNewAlerts(sarifResponse *Log, ruleID string) bool {
	newAlertsCountByRuleID := make(map[string]int)
	for _, run := range sarifResponse.Runs {
		for _, result := range run.Results {
			for _, location := range result.Locations {
				location.PhysicalLocation.ArtifactLocation.URI = strings.Replace(location.PhysicalLocation.ArtifactLocation.URI, "file:///home/validator/src/", "", 1)
			}
			// match ruleId
			ruleID := result.RuleID
			resultCount := len(strings.Split(result.Message.Text, "\n")) + 1
			if count, exists := newAlertsCountByRuleID[ruleID]; exists {
				newAlertsCountByRuleID[ruleID] = count + resultCount
			} else {
				newAlertsCountByRuleID[ruleID] = resultCount
			}
		}
	}

	if count, exists := newAlertsCountByRuleID[ruleID]; exists && count > 0 {
		return true
	}

	return false
}

// FilterRelevantAlerts filters SARIF results to include only those alerts that pertain to the changed code regions.
// FilterRelevantAlerts returns a deep-copied Log containing only results/locations
// whose locations overlap with the provided changed code regions. Any Result that
// has no remaining relevant locations is dropped. Runs with no remaining results
// are also omitted. The original log is not mutated.
func FilterRelevantAlerts(log *Log, changedCodeRegions []diff.ChangedCodeRegion) *Log {
	if log == nil {
		return nil
	}

	// Map new file to list of code ranges for fast lookup.
	relevantLocations := make(map[string][]diff.CodeRange)
	for _, region := range changedCodeRegions {
		relevantLocations[region.NewFile] = append(relevantLocations[region.NewFile], region.NewLineRange)
	}

	filteredRuns := make([]Run, 0, len(log.Runs))
	for _, run := range log.Runs {
		newResults := make([]Result, 0, len(run.Results))
		for _, res := range run.Results {
			newLocations := make([]LocWrap, 0, len(res.Locations))
			for _, loc := range res.Locations {
				filePath := loc.PhysicalLocation.ArtifactLocation.URI
				codeRanges, found := relevantLocations[filePath]
				if !found {
					// Perform suffix match (handles absolute paths in SARIF vs relative paths in diff regions)
					for relevantFile := range relevantLocations {
						if strings.HasSuffix(filePath, relevantFile) {
							codeRanges = relevantLocations[relevantFile]
							found = true
							break
						}
					}
					if !found { // still not relevant
						continue
					}
				}

				region := loc.PhysicalLocation.Region
				startLine := region.StartLine
				endLine := region.EndLine

				// Retain this location if it is fully contained in or fully contains one of the changed ranges.
				for _, r := range codeRanges {
					if startLine >= r.Start && endLine <= r.End || startLine <= r.Start && endLine >= r.End {
						// Copy the location
						newLoc := loc
						newLocations = append(newLocations, newLoc)
						break
					}
				}
			}
			if len(newLocations) > 0 { // keep only results with at least one relevant location
				newRes := res // copy res
				newRes.Locations = newLocations
				newResults = append(newResults, newRes)
			}
		}
		if len(newResults) > 0 { // keep only runs with at least one relevant result
			newRun := run // copy run
			newRun.Results = newResults
			filteredRuns = append(filteredRuns, newRun)
		}
	}

	return &Log{Version: log.Version, Schema: log.Schema, Runs: filteredRuns}
}
