package sessions

import (
	"testing"

	"github.com/github/turboscan/ts/cassettes"
)

func TestMAAnalyses(t *testing.T) {
	var repositoryID uint64 = 351
	session := cassettes.NewSession(t)

	session.Analyze(t, repositoryID, "./data/7e084a1.sarif", "dynamic/github-code-scanning/codeql:", "refs/heads/master")

	session.Replay(t, "code-scanning/get-analyses-ma.yml")
}
