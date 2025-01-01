package sessions_test

import (
	"testing"

	"github.com/github/turboscan/ts/cassettes"
)

// TestWithExtensions uploads a SARIF file with extensions and then records the output of the SARIF builder
func TestWithExtensions(t *testing.T) {
	var repositoryID uint64 = 351
	session := cassettes.NewSession(t)

	session.Analyze(t, repositoryID, "./data/extensions.sarif", ".github/workflows/w1.yml:job1", "refs/heads/master")

	session.Replay(t, "code-scanning/analysis-extensions-sarif.yml")

}
