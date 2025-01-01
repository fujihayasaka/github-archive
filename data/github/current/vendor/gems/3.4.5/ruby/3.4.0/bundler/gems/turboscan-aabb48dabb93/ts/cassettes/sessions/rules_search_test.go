package sessions_test

import (
	"testing"

	"github.com/github/turboscan/ts/cassettes"
)

// TestRules calls the GetRules endpoint
func TestRulesWithSearch(t *testing.T) {
	var repositoryID uint64 = 351
	session := cassettes.NewSession(t)

	session.Analyze(t, repositoryID, "./data/7e084a1.sarif", ".github/workflows/w1.yml:job1", "refs/heads/master")

	session.Replay(t, "code-scanning/rules-search.yml")
}
