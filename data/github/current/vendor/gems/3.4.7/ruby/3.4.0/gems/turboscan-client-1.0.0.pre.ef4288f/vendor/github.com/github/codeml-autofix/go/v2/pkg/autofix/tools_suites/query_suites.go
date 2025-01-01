// Package toolsuites provides functionality for managing and querying sets of queries (QuerySuites)
// used for testing, validation, or analysis purposes. It supports embedding suite definitions,
// loading supported queries for specific languages and tools, and checking query inclusion within suites.
package toolsuites

import (
	"encoding/json"
	"fmt"
	"io/fs"
	"log"
	"os"
	"slices"

	"embed"

	"github.com/github/code-scanning-ai-libraries/v2/st"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/utils"
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

//go:embed .generated/query-suites
var embeddedSuites embed.FS

var suites fs.FS = embeddedSuites

const (
	ErrQuerySuiteFileNotFound  = "Query suite file not found"
	ErrFailedToLoadQuerySuite  = "Failed to load query suite"
	ErrFailedToParseQuerySuite = "Failed to parse query suite file"
)

// QuerySuite represents a set of queries that can be used to test a rule.
const (
	Default           QuerySuite = "default"
	CodeScanning      QuerySuite = "code-scanning"
	Extended          QuerySuite = "extended"
	CopilotCodeReview QuerySuite = "ccr"
)

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
	suiteFilePath := fmt.Sprintf(".generated/query-suites/%s/%s_ids-%s.json", language, qs, tool)

	data, err := fs.ReadFile(suites, suiteFilePath)
	if err != nil {
		if os.IsNotExist(err) {
			errorMsg := errors.Errorf("%s at %s", ErrQuerySuiteFileNotFound, suiteFilePath)
			log.Println(errorMsg)
			return []QueryID{}, errorMsg
		}
		errorMsg := st.EnsureStackTracef(err, "%s from %s", ErrFailedToLoadQuerySuite, suiteFilePath)
		log.Println(errorMsg)
		return []QueryID{}, errorMsg
	}

	var queryIDs []QueryID
	if err := json.Unmarshal(data, &queryIDs); err != nil {
		errorMsg := st.EnsureStackTracef(err, "%s %s", ErrFailedToLoadQuerySuite, suiteFilePath)
		log.Println(errorMsg)
		return []QueryID{}, errorMsg
	}

	return queryIDs, nil
}
