// Package toolsuites provides functionality for managing and querying sets of queries (QuerySuites)
// used for testing, validation, or analysis purposes. It supports embedding suite definitions,
// loading supported queries for specific languages and tools, and checking query inclusion within suites.
package toolsuites

import (
	_ "embed"
	"encoding/json"
	"log"
	"slices"

	"github.com/github/code-scanning-ai-libraries/v4/st"
	"github.com/github/codeml-autofix/go/v4/pkg/autofix/utils"
	"github.com/pkg/errors"
)

// QuerySuite represents a suite of queries used for testing or validation purposes.
// It typically contains a collection of queries grouped together for execution or analysis.
type QuerySuite string

// QueryID uniquely identifies a specific query within a QuerySuite or across the system.
// It is used to reference and manage queries programmatically.
type QueryID string

// Create a query set key for context if needed
type querySuiteKeyType string

// QuerySuiteKey is the context key used for storing the active query suite.
const QuerySuiteKey querySuiteKeyType = "query_suite"

//go:embed .generated/tool-coverage.json
var toolCoverageData []byte

const (
	// ErrQuerySuiteFileNotFound error message when the query suite file is not found
	ErrQuerySuiteFileNotFound = "Query suite file not found"

	// ErrFailedToLoadQuerySuite error message when the query suite fails to load
	ErrFailedToLoadQuerySuite = "Failed to load query suite"

	// ErrFailedToParseQuerySuite error message when the query suite fails to parse
	ErrFailedToParseQuerySuite = "Failed to parse query suite file"
)

// QuerySuite represents a set of queries that can be used to test a rule.
const (
	Default           QuerySuite = "default"
	CodeScanning      QuerySuite = "code-scanning"
	Extended          QuerySuite = "extended"
	CopilotCodeReview QuerySuite = "ccr"
)

// QueryInfo contains information about a query including which suites it belongs to.
type QueryInfo struct {
	Suites []QuerySuite `json:"suites"`
}

// LanguageQueries maps query IDs to their query info for a specific language.
type LanguageQueries map[QueryID]QueryInfo

// ToolQueries maps languages to their queries for a specific tool.
type ToolQueries map[utils.Language]LanguageQueries

// ToolCoverage represents the complete tool coverage data structure.
type ToolCoverage map[Tool]ToolQueries

var toolCoverage ToolCoverage

// GetToolCoverage reads and parses the tool-coverage.json file into a structured format.
func GetToolCoverage() (ToolCoverage, error) {
	data := toolCoverageData
	if data == nil {
		errorMsg := errors.Errorf("Tool coverage file not found")
		log.Println(errorMsg)
		return nil, errorMsg
	}

	var coverage ToolCoverage
	if err := json.Unmarshal(data, &coverage); err != nil {
		errorMsg := st.EnsureStackTracef(err, "Failed to parse tool coverage file .generated/tool-coverage.json")
		log.Println(errorMsg)
		return nil, errorMsg
	}

	return coverage, nil
}

// IsIncluded reports whether a query id is part of the suite for the given language and tool.
func (qs QuerySuite) IsIncluded(queryID QueryID, language utils.Language, tool Tool) (bool, error) {
	supportedQueries, err := qs.GetSupportedQueries(language, tool)
	if err != nil {
		return false, err
	}

	return slices.Contains(supportedQueries, queryID), nil
}

// GetSupportedQueries returns a list of queries that are supported by a given suite for a given tool.
func (qs QuerySuite) GetSupportedQueries(language utils.Language, tool Tool) ([]QueryID, error) {
	initToolCoverage()
	coverageForTool, ok := toolCoverage[tool]
	if !ok {
		return []QueryID{}, errors.Errorf("No coverage information for tool %s", tool)
	}

	languageQueries, ok := coverageForTool[language]
	if !ok {
		return []QueryID{}, errors.Errorf("No coverage information for language %s and tool %s", language, tool)
	}

	var queryIDs []QueryID
	var foundOtherSuites bool
	for queryID, queryInfo := range languageQueries {
		for _, suite := range queryInfo.Suites {
			if suite == qs {
				queryIDs = append(queryIDs, queryID)
			} else {
				foundOtherSuites = true
			}
		}
	}
	if len(queryIDs) == 0 && foundOtherSuites {
		return []QueryID{}, errors.Errorf("Suite %s not found for language %s and tool %s", qs, language, tool)
	} else if len(queryIDs) == 0 {
		return []QueryID{}, errors.Errorf("No queries found for suite %s, language %s and tool %s", qs, language, tool)
	}
	return queryIDs, nil
}

// GetEnabledTools returns a map of tools that are enabled based on the tool coverage data.
func GetEnabledTools() map[Tool]bool {
	initToolCoverage()
	tools := make(map[Tool]bool)
	for tool := range toolCoverage {
		tools[tool] = true
	}
	return tools
}

func initToolCoverage() {
	if len(toolCoverage) == 0 {
		var err error
		toolCoverage, err = GetToolCoverage()
		if err != nil {
			panic("Failed to load tool coverage: " + err.Error())
		}
	}
}
