package sessions_test

import (
	"testing"

	"github.com/github/turboscan/ts/cassettes"
)

// TestDelivery creates different types of response for the Delivery endpoint
func TestDelivery(t *testing.T) {
	var repositoryIDForErrorCase uint64 = 352
	var repositoryIDForSuccessCase uint64 = 353
	var repositoryIDForPullRequestCase uint64 = 354
	var repositoryIDForPendingCase uint64 = 355
	session := cassettes.NewSession(t)

	// A failed delivery with a ProcessError won't create an analysis
	sarifID1 := "e4e4bbcd-9f4e-4ddd-8e83-66eb9127a6df"
	session.Analyze(t, repositoryIDForErrorCase, "./data/corrupt.sarif.gz", ".github/workflows/codeql.yml:CodeQL", "refs/heads/main", cassettes.WithSarifID(sarifID1))

	// The response is still considered an error even with a successful delivery for the same repository + SARIF ID
	// So add a successful delivery for the same repository + SARIF ID to allow us to test that.
	session.Analyze(t, repositoryIDForErrorCase, "./data/3alerts.sarif", ".github/workflows/codeql.yml:CodeQL", "refs/heads/aaa", cassettes.WithSarifID(sarifID1))

	// The other repo has only had a successful delivery, and no errors
	sarifID2 := "ecf5f4e0-5c8a-4284-8aad-d61b38b1145e"
	session.Analyze(t, repositoryIDForSuccessCase, "./data/3alerts.sarif", ".github/workflows/codeql.yml:CodeQL", "refs/heads/aaa", cassettes.WithSarifID(sarifID2))

	session.Replay(t, "code-scanning/delivery-error.yml")

	session.Replay(t, "code-scanning/delivery-no-error.yml")

	session.Replay(t, "code-scanning/delivery-not-found.yml")

	session.Analyze(t, repositoryIDForPullRequestCase, "./data/3alerts.sarif", ".github/workflows/codeql.yml:CodeQL", "refs/pull/1/merge", cassettes.WithSarifID("40c14d98-494d-46f0-b1b8-c1bb22f89db1"))
	session.Replay(t, "code-scanning/delivery-for-pull-request.yml")

	session.CreatePendingDelivery(t, repositoryIDForPendingCase, "refs/heads/pending", cassettes.WithSarifID("34d1cd5e-ba30-4c40-ac92-33ee32d6acbb"))
	session.Replay(t, "code-scanning/delivery-pending.yml")
}

// TestCreateDelivery creates a delivery asynchronously
func TestCreateDelivery(t *testing.T) {
	session := cassettes.NewSession(t)

	session.Replay(t, "code-scanning/create-delivery.yml")
}
