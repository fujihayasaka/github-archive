package sessions

import (
	"testing"

	"github.com/github/turboscan/ts"

	"github.com/github/turboscan/ts/cassettes"
)

func TestEvalRefUpdateRules(t *testing.T) {
	var repositoryID uint64 = 105
	session := cassettes.NewSession(t)

	commit := "480d4f47447129f015cb327536c522ca683939a1"

	// The alert we get here has severity WARNING and security severity CRITICAL
	session.Analyze(t, repositoryID, "./data/empty.sarif", "a", "refs/heads/main")
	session.Analyze(t, repositoryID, "./data/1-critical-sec-sev.sarif", "a", "refs/pull/1/merge", cassettes.WithCommitOid(commit))

	session.Replay(t, "code-scanning/eval-ref-update-rules-fail1.yml")
	session.Replay(t, "code-scanning/eval-ref-update-rules-pass1.yml")
	session.Replay(t, "code-scanning/eval-ref-update-rules-many-configs.yml")
}

func TestEvalRefUpdateDependabot(t *testing.T) {
	var repositoryID ts.RepositoryEID = 351
	var workflowRunID ts.WorkflowRunEID = 5
	session := cassettes.NewSession(t)

	session.DisableTestFailuresForEnablementStatusExceptions()
	session.Replay(t, "code-scanning/managed-analyses-enable-js-only.yml")
	session.UpsertCodeqlRunStatus(t, repositoryID, workflowRunID, ts.CodeqlRunStatus_COMPLETED)

	session.Replay(t, "code-scanning/eval-ref-update-rules-pass-dependabot.yml")
}

func TestEvalRefUpdateRulesMissingCategories(t *testing.T) {
	var repositoryID uint64 = 105
	session := cassettes.NewSession(t)

	commitA := "a270ea0fdfba2bd5a33934e5184784cddce87f38"
	commitB := "480d4f47447129f015cb327536c522ca683939a1"

	session.Analyze(t, repositoryID, "./data/1-error.sarif", "a", "refs/heads/main", cassettes.WithCommitOid(commitA))
	session.Analyze(t, repositoryID, "./data/1-error.sarif", "b", "refs/heads/main", cassettes.WithCommitOid(commitA))
	session.Analyze(t, repositoryID, "./data/1-error.sarif", "c", "refs/heads/main", cassettes.WithCommitOid(commitA))
	session.Analyze(t, repositoryID, "", "c", "refs/heads/main", cassettes.WithCommitOid(commitA), cassettes.WithIsOutdated("Old CodeQL", "c"))
	session.Analyze(t, repositoryID, "./data/1-warning.sarif", "a", "refs/pull/1/merge", cassettes.WithCommitOid(commitB))

	session.Replay(t, "code-scanning/eval-ref-update-rules-missing-categories.yml")
}

func TestEvalRefUpdateRulesMissingCategoriesForSecondTool(t *testing.T) {
	var repositoryID uint64 = 105
	session := cassettes.NewSession(t)

	commitA := "a270ea0fdfba2bd5a33934e5184784cddce87f38"
	commitB := "480d4f47447129f015cb327536c522ca683939a1"

	// Data for Old CodeQL
	session.Analyze(t, repositoryID, "./data/1-error.sarif", "a", "refs/heads/main", cassettes.WithCommitOid(commitA))
	session.Analyze(t, repositoryID, "./data/1-error.sarif", "b", "refs/heads/main", cassettes.WithCommitOid(commitA))
	session.Analyze(t, repositoryID, "./data/1-error.sarif", "c", "refs/heads/main", cassettes.WithCommitOid(commitA))
	session.Analyze(t, repositoryID, "", "c", "refs/heads/main", cassettes.WithCommitOid(commitA), cassettes.WithIsOutdated("Old CodeQL", "c"))
	session.Analyze(t, repositoryID, "./data/1-warning.sarif", "a", "refs/pull/1/merge", cassettes.WithCommitOid(commitB))

	// Data for CodeQL
	session.Analyze(t, repositoryID, "./data/1-critical-sec-sev.sarif", "a", "refs/pull/1/merge", cassettes.WithCommitOid(commitB))

	session.Replay(t, "code-scanning/eval-ref-update-rules-missing-categories-for-second-tool.yml")
}

func TestEvalRefUpdateRulesMissingResultsForSecondTool(t *testing.T) {
	var repositoryID uint64 = 105
	var otherRepositoryID uint64 = 42
	session := cassettes.NewSession(t)

	commit := "480d4f47447129f015cb327536c522ca683939a1"

	// Analyze something with CodeQL in the other repo so the tool gets created.
	session.Analyze(t, otherRepositoryID, "./data/1-error.sarif", "a", "refs/heads/main", cassettes.WithCommitOid(commit))

	// Analyze with Old CodeQL in the actual repo.
	session.Analyze(t, repositoryID, "./data/1-warning.sarif", "a", "refs/pull/1/merge", cassettes.WithCommitOid(commit))

	session.Replay(t, "code-scanning/eval-ref-update-rules-missing-results-for-second-tool.yml")
}

func TestEvalRefUpdateRulesMissingResultsForSecondUnknownTool(t *testing.T) {
	//  This test is like TestEvalRefUpdateRulesMissingResultsForSecondTool but here the second tool (CodeQL) is not known to Turboscan at all.
	var repositoryID uint64 = 105
	session := cassettes.NewSession(t)

	commit := "480d4f47447129f015cb327536c522ca683939a1"

	session.Analyze(t, repositoryID, "./data/1-warning.sarif", "a", "refs/pull/1/merge", cassettes.WithCommitOid(commit))

	session.ReplayReadOnly(t, "code-scanning/eval-ref-update-rules-missing-results-for-second-tool.yml")
}
