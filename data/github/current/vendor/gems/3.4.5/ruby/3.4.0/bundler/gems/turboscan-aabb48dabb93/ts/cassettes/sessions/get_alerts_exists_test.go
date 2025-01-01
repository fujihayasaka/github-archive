package sessions_test

import (
	"testing"

	"github.com/github/turboscan/ts/cassettes"
)

// TestAlertsAnalysisExists tests the analysis exists property of the get_alerts endpoint
func TestAlertsAnalysisExists(t *testing.T) {
	var repositoryID uint64 = 351
	session := cassettes.NewSession(t)

	// Two analyses:
	// - one on master for CodeQL
	// - one on develop for "Some other tool"
	session.Analyze(t,
		repositoryID,
		"./data/empty.sarif",
		".github/workflows/codeql.yml:CodeQL",
		"refs/heads/master",
	)

	session.Analyze(t,
		repositoryID,
		"./data/other.sarif",
		".github/workflows/codeql.yml:Other",
		"refs/heads/develop",
	)

	// Contains 4 requests:
	// 1. master filter, no tool filter => analysis exists
	// 2. master filter, filter to CodeQL => analysis exists
	// 3. master filter, filter to "Some other tool" => analysis exists (only ref is relevant here)
	// 4. missing ref filter => analysis does not exist
	session.Replay(t, "code-scanning/get-alerts-analysis-exists.yml")
}
