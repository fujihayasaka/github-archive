package sessions_test

import (
	"testing"

	"github.com/github/turboscan/ts/cassettes"
)

func TestCreateSecurityCampaignAlerts(t *testing.T) {
	var orgID uint64 = 71
	var repositoryID uint64 = 351
	session := cassettes.NewSessionWithES(t)

	session.Analyze(t, repositoryID, "./data/3alerts.sarif", ".github/workflows/w1.yml:job1", "refs/heads/master")
	session.IndexWithRepoMetadata(t, repositoryID, orgID, "refs/heads/master", "public", true)

	session.Replay(t, "code-scanning/create-security-campaign-alerts.yml")

	// Make sure changes to the ES index are reflected in the search results
	session.RefreshES(t)
	session.Replay(t, "code-scanning/org-security-campaign.yml")
	session.Replay(t, "code-scanning/counts-by-campaigns.yml")
	session.Replay(t, "code-scanning/repo-counts-by-campaigns.yml")
}
