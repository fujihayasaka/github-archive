package sessions_test

import (
	"testing"

	"github.com/github/turboscan/ts/cassettes"
)

func TestGetAlertsWithNumbersFilter(t *testing.T) {
	var repositoryID uint64 = 351
	session := cassettes.NewSession(t)

	session.Analyze(t, repositoryID, "./data/numbers-java.sarif", ".github/workflows/w1.yml:java", "refs/heads/main")
	session.Analyze(t, repositoryID, "./data/numbers-javascript.sarif", ".github/workflows/w1.yml:javascript", "refs/heads/main")

	// Fix all JS alerts
	session.Analyze(t, repositoryID, "./data/empty.sarif", ".github/workflows/w1.yml:javascript", "refs/heads/main")

	session.Replay(t, "code-scanning/get-alerts-numbers-filter.yml")
	session.Replay(t, "code-scanning/get-alerts-numbers-filter-all.yml")
}
