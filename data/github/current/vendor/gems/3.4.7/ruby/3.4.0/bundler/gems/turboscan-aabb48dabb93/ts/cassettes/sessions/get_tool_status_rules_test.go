package sessions

import (
	"testing"

	"github.com/github/turboscan/ts/cassettes"
)

func TestGetToolStatusRules(t *testing.T) {
	var repositoryID uint64 = 351

	session := cassettes.NewSession(t)

	session.Analyze(t, repositoryID, "./data/3-warnings-1-note.sarif", ".github/workflows/w1.yml:job1", "refs/heads/master", cassettes.WithTrackStatus())

	session.Replay(t, "code-scanning/get-tool-status-rules.yml")
}
