package sessions_test

import (
	"testing"

	"github.com/github/turboscan/ts/cassettes"
)

func TestDeleteAlertLinks(t *testing.T) {
	var repositoryID uint64 = 351
	session := cassettes.NewSessionWithES(t)

	session.Analyze(t, repositoryID, "./data/3alerts.sarif", ".github/workflows/w1.yml:job1", "refs/heads/master")
	session.Replay(t, "code-scanning/create-alert-links-pull-request.yml")
	session.Replay(t, "code-scanning/create-alert-links-ref.yml")

	session.Replay(t, "code-scanning/delete-alert-links.yml")
	session.Replay(t, "code-scanning/get-links-for-alert-after-deletion.yml")
}
