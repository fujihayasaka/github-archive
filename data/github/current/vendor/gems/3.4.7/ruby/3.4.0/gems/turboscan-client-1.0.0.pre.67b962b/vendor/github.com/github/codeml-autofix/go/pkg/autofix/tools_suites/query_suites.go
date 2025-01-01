package autofix

import (
	"encoding/json"
	"fmt"
	"log"
	"os"
	"slices"

	"embed"
	"github.com/github/codeml-autofix/go/pkg/autofix/utils"
)

type QuerySuite string
type QueryId string

//go:generate ../../../bin/metagen query-suites
//go:embed .generated/query-suites
var suites embed.FS

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

func (qs QuerySuite) IsIncluded(queryId QueryId, language utils.Language, tool Tool) (bool, error) {
	supportedQueries, err := qs.GetSupportedQueries(language, tool)
	if err != nil {
		return false, err
	}

	return slices.Contains(supportedQueries, queryId), nil
}

// GetSupportedQueries returns a list of queries that are supported by a given suite for a given tool.
func (qs QuerySuite) GetSupportedQueries(language utils.Language, tool Tool) ([]QueryId, error) {
	suiteFilePath := fmt.Sprintf(".generated/query-suites/%s/%s_ids-%s.json", language, qs, tool)

	data, err := suites.ReadFile(suiteFilePath)
	if err != nil {
		if os.IsNotExist(err) {
			errorMsg := fmt.Errorf("%s at %s", ErrQuerySuiteFileNotFound, suiteFilePath)
			log.Println(errorMsg)
			return []QueryId{}, errorMsg
		}
		errorMsg := fmt.Errorf("%s from %s: %v", ErrFailedToLoadQuerySuite, suiteFilePath, err)
		log.Println(errorMsg)
		return []QueryId{}, errorMsg
	}

	var queryIds []QueryId
	if err := json.Unmarshal(data, &queryIds); err != nil {
		errorMsg := fmt.Errorf("%s %s: %v", ErrFailedToLoadQuerySuite, suiteFilePath, err)
		log.Println(errorMsg)
		return []QueryId{}, errorMsg
	}

	return queryIds, nil
}
