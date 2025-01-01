package sessions

import (
	"os"
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/cassettes"
)

func TestGetSuggestedFix(t *testing.T) {
	var repositoryID uint64 = 351
	repositoryEID := ts.RepositoryEID(repositoryID)
	commitA := "a270ea0fdfba2bd5a33934e5184784cddce87f38"
	ref := "refs/pull/42/merge"

	session := cassettes.NewSession(t)
	session.Analyze(t, repositoryID, "./data/2-alerts-in-separate-files.sarif", ".github/workflows/w1.yml:job1", ref, cassettes.WithCommitOid(commitA))

	description1 := "To fix this vulnerability, we need to sanitize the user input before incorporating it into the response. We can use the `escape-html` library to escape any potentially harmful characters in the user input.\n\nThe best way to fix the vulnerability without changing existing functionality is to add an import for the `escape-html` library at the top of the file and then use the `escape` function to sanitize the `req.query.name` before incorporating it into the response.\n\nHere's what needs to be changed in the index.js file:\n\n1. Add an import for the `escape-html` library at the top of the file.\n2. Replace the line that incorporates the user input into the response with a sanitized version of the input.\n"

	fileDiffs1 := [][]byte{
		[]byte("--- a/index.js\n+++ b/index.js\n@@ -1 +1,2 @@\n+const escape = require('escape-html');\n const express = require('express');\n@@ -3,2 +4,2 @@\n const app = express();\n-app.get('/', (req, res) => res.send(`Hello, ${req.query.name}!`));\n\\ No newline at end of file\n+app.get('/', (req, res) => res.send(`Hello, ${escape(req.query.name)}!`));\n\\ No newline at end of file\n"),
		[]byte("--- a/package.json\n+++ b/package.json\n@@ -9,3 +9,4 @@\n   \"dependencies\": {\n-    \"express\": \"^4.17.1\"\n+    \"express\": \"^4.17.1\",\n+    \"escape-html\": \"^1.0.3\"\n   },\n"),
	}

	description2 := "To fix this vulnerability, we need to remove the logging of sensitive information, specifically the `password` variable on line 99. The best way to fix this vulnerability is to simply remove the `console.log` statement that logs the sensitive data.\n"

	fileDiffs2 := [][]byte{
		[]byte("--- a/src/server/passport.js\n+++ b/src/server/passport.js\n@@ -95,9 +95,9 @@\n \t\t\tdb.query(`select * from accounts where email = ?`, [username], (err, user) => {\n \t\t\t\tif (err) console.log(err)\n \t\t\t\tif (!user.length) done(null, false, {message: 'Incorrect user name'})\n \t\t\t\tif (user.length) {\n-\t\t\t\t\tconsole.log( password, user[0].encrypted_credentials )\n+\t\t\t\t\t// console.log( password, user[0].encrypted_credentials )\n \t\t\t\t\tbcrypt.compare(password, user[0].encrypted_credentials, (err, result) => {\n \t\t\t\t\t\tif (err) console.log(err)\n \t\t\t\t\t\tconsole.log(result)\n \t\t\t\t\t\treturn result ? done(null, user) : done(null, false, {message: 'Wrong password'})\n"),
	}

	session.CreateSuggestedFix(t, repositoryEID, 1, 1, description1, fileDiffs1, commitA, ref, nil)
	session.CreateSuggestedFix(t, repositoryEID, 2, 2, description2, fileDiffs2, commitA, ref, nil)
	session.Replay(t, "code-scanning/get-suggested-fix.yml")
}

func TestGetSuggestedFix_Golang(t *testing.T) {
	var repositoryID uint64 = 351
	repositoryEID := ts.RepositoryEID(repositoryID)
	commitA := "a270ea0fdfba2bd5a33934e5184784cddce87f38"
	ref := "refs/pull/42/merge"

	session := cassettes.NewSession(t)
	session.Analyze(t, repositoryID, "./data/golang-single-alert.sarif", ".github/workflows/w1.yml:job1", ref, cassettes.WithCommitOid(commitA))

	description1 := "To fix this vulnerability, we need to sanitize the user input before incorporating it into the response. We can use the `escape-html` library to escape any potentially harmful characters in the user input.\n\nThe best way to fix the vulnerability without changing existing functionality is to add an import for the `escape-html` library at the top of the file and then use the `escape` function to sanitize the `req.query.name` before incorporating it into the response.\n\nHere's what needs to be changed in the index.js file:\n\n1. Add an import for the `escape-html` library at the top of the file.\n2. Replace the line that incorporates the user input into the response with a sanitized version of the input.\n"

	fileDiffs := [][]byte{
		[]byte("--- a/main.go\n+++ b/main.go\n@@ -10,4 +10,4 @@\n func checkRedirect2(req *http.Request, via []*http.Request) error {\n-\tre := \"https?://gggiiiiiithub\\\\.com/\"\n-\tif matched, _ := regexp.MatchString(re, req.URL.String()); matched { // go/regex/missing-regexp-anchor\n+\tre := \"^https?://gggiiiiiithub\\\\.com/$\"\n+\tif matched, _ := regexp.MatchString(re, req.URL.String()); matched {\n \t\treturn nil\n"),
	}

	session.CreateSuggestedFix(t, repositoryEID, 1, 1, description1, fileDiffs, commitA, ref, nil)
	session.Replay(t, "code-scanning/get-one-suggested-fix.yml")
}

func TestGetSuggestedFixWithAnnotation_Error(t *testing.T) {
	var repositoryID uint64 = 351
	repositoryEID := ts.RepositoryEID(repositoryID)
	commitA := "a270ea0fdfba2bd5a33934e5184784cddce87f38"
	ref := "refs/pull/42/merge"

	session := cassettes.NewSession(t)
	session.Analyze(t, repositoryID, "./data/2-alerts-in-separate-files.sarif", ".github/workflows/w1.yml:job1", ref, cassettes.WithCommitOid(commitA))

	session.CreateEmptySuggestedFix(t, repositoryEID, 1, 1, ref, ts.SuggestedFixAlertStateError)
	session.Replay(t, "code-scanning/get-error-suggested-fix-and-annotations.yml")
}

func TestGetSuggestedFixWithAnnotation_Invalid(t *testing.T) {
	var repositoryID uint64 = 351
	repositoryEID := ts.RepositoryEID(repositoryID)
	commitA := "a270ea0fdfba2bd5a33934e5184784cddce87f38"
	ref := "refs/pull/42/merge"

	session := cassettes.NewSession(t)
	session.Analyze(t, repositoryID, "./data/2-alerts-in-separate-files.sarif", ".github/workflows/w1.yml:job1", ref, cassettes.WithCommitOid(commitA))

	session.CreateEmptySuggestedFix(t, repositoryEID, 1, 1, ref, ts.SuggestedFixAlertStateInvalid)
	session.Replay(t, "code-scanning/get-invalid-suggested-fix-and-annotations.yml")
}

func TestGetCreateAndUpdateSuggestedFix(t *testing.T) {
	session := cassettes.NewSession(t)

	repositoryID := uint64(351)
	ref := "refs/pull/42/merge"

	// A PR is opened and an analysis with one vulnerability is pushed
	commit1 := "a270ea0fdfba2bd5a33934e5184784cddce87f38"
	session.MockSuggestedFixFile(t, "index.js", commit1, []byte("index.js content"))
	session.MockSuggestedFixFile(t, "package.json", commit1, []byte("package.json content"))
	session.Analyze(t, repositoryID, "../../cocofix/testdata/reflected-xss.sarif", ".github/workflows/codeql.yml:CodeQL", ref, cassettes.WithCommitOid(commit1))

	// GetSuggestedFix works as expected when no fix was requested
	session.Replay(t, "code-scanning/get-suggested-fix-no-fix.yml")

	// Request the generation of a suggested fix
	session.Replay(t, "code-scanning/generate-suggested-fix.yml")
	session.Replay(t, "code-scanning/get-suggested-fix-pending.yml") // The suggested fix should now be pending

	// Run the job that generates the fix
	session.PerformJob(t, "turboscan-suggested-fix-generate-high-priority")
	session.Replay(t, "code-scanning/get-suggested-fix-valid.yml") // GetSuggestedFix returns the generated fix

	// The PR gets updated with a new commit
	commit2 := "480d4f47447129f015cb327536c522ca683939a1"
	session.MockSuggestedFixFile(t, "index.js", commit2, []byte("index.js new content"))
	session.Replay(t, "code-scanning/get-suggested-fix-outdated-commit2.yml") // GetSuggestedFix returns the now outdated fix

	// The analysis finish and gets published to turboscan
	session.Analyze(t, repositoryID, "../../cocofix/testdata/reflected-xss.sarif", ".github/workflows/codeql.yml:CodeQL", ref, cassettes.WithCommitOid(commit2))
	session.ReplayReadOnly(t, "code-scanning/get-suggested-fix-outdated-commit2.yml") // GetSuggestedFix still returns the outdated fix

	// The alert still present, so a new generation is triggered
	session.Replay(t, "code-scanning/generate-suggested-fix-commit2.yml")
	session.Replay(t, "code-scanning/get-suggested-fix-pending-commit2.yml") // Since the files changed, cannot use the fix from the cache and it should generate a new one

	// Run the job that generates the fix
	session.PerformJob(t, "turboscan-suggested-fix-generate-high-priority")
	session.Replay(t, "code-scanning/get-suggested-fix-valid-commit2.yml") // GetSuggestedFix returns the regenerated fix
}

func TestGetSuggestedFixAndAnnotations(t *testing.T) {
	var repositoryID uint64 = 351
	repositoryEID := ts.RepositoryEID(repositoryID)
	commitA := "a270ea0fdfba2bd5a33934e5184784cddce87f38"
	ref := "refs/pull/42/merge"

	session := cassettes.NewSession(t)
	session.Analyze(t, repositoryID, "../../cocofix/testdata/reflected-xss.sarif", "a", ref, cassettes.WithCommitOid(commitA))
	session.Analyze(t, repositoryID, "../../cocofix/testdata/made-up-alert.sarif", "b", ref, cassettes.WithCommitOid(commitA))
	session.Analyze(t, repositoryID, "./data/3-warnings-1-note.sarif", "c", ref, cassettes.WithCommitOid(commitA))
	session.Analyze(t, repositoryID, "./data/3alerts.sarif", "d", ref, cassettes.WithCommitOid(commitA))

	description1 := "To fix this vulnerability, we need to sanitize the user input before incorporating it into the response. We can use the `escape-html` library to escape any potentially harmful characters in the user input.\n\nThe best way to fix the vulnerability without changing existing functionality is to add an import for the `escape-html` library at the top of the file and then use the `escape` function to sanitize the `req.query.name` before incorporating it into the response.\n\nHere's what needs to be changed in the index.js file:\n\n1. Add an import for the `escape-html` library at the top of the file.\n2. Replace the line that incorporates the user input into the response with a sanitized version of the input.\n"

	fileDiffs1 := [][]byte{
		[]byte("--- a/index.js\n+++ b/index.js\n@@ -1 +1,2 @@\n+const escape = require('escape-html');\n const express = require('express');\n@@ -3,2 +4,2 @@\n const app = express();\n-app.get('/', (req, res) => res.send(`Hello, ${req.query.name}!`));\n\\ No newline at end of file\n+app.get('/', (req, res) => res.send(`Hello, ${escape(req.query.name)}!`));\n\\ No newline at end of file\n"),
		[]byte("--- a/package.json\n+++ b/package.json\n@@ -9,3 +9,4 @@\n   \"dependencies\": {\n-    \"express\": \"^4.17.1\"\n+    \"express\": \"^4.17.1\",\n+    \"escape-html\": \"^1.0.3\"\n   },\n"),
	}

	description2 := "To fix this vulnerability, we need to remove the logging of sensitive information, specifically the `password` variable on line 99. The best way to fix this vulnerability is to simply remove the `console.log` statement that logs the sensitive data.\n"

	fileDiffs2 := [][]byte{
		[]byte("--- a/src/server/passport.js\n+++ b/src/server/passport.js\n@@ -95,9 +95,9 @@\n \t\t\tdb.query(`select * from accounts where email = ?`, [username], (err, user) => {\n \t\t\t\tif (err) console.log(err)\n \t\t\t\tif (!user.length) done(null, false, {message: 'Incorrect user name'})\n \t\t\t\tif (user.length) {\n-\t\t\t\t\tconsole.log( password, user[0].encrypted_credentials )\n+\t\t\t\t\t// console.log( password, user[0].encrypted_credentials )\n \t\t\t\t\tbcrypt.compare(password, user[0].encrypted_credentials, (err, result) => {\n \t\t\t\t\t\tif (err) console.log(err)\n \t\t\t\t\t\tconsole.log(result)\n \t\t\t\t\t\treturn result ? done(null, user) : done(null, false, {message: 'Wrong password'})\n"),
	}

	session.CreateSuggestedFix(t, repositoryEID, 1, 1, description1, fileDiffs1, commitA, ref, nil)
	session.CreateSuggestedFix(t, repositoryEID, 2, 2, description2, fileDiffs2, commitA, ref, nil)
	session.CreateSuggestedFix(t, repositoryEID, 3, 3, description2, fileDiffs2, commitA, ref, nil)
	session.CreateSuggestedFix(t, repositoryEID, 4, 4, description2, fileDiffs2, commitA, ref, nil)

	session.CreateEmptySuggestedFix(t, repositoryEID, 5, 5, ref, ts.SuggestedFixAlertStatePending)
	session.CreateEmptySuggestedFix(t, repositoryEID, 7, 7, ref, ts.SuggestedFixAlertStateRuleNotSupported)

	// Mark alert 3 as resolved
	session.ResolveAlert(t, repositoryEID, 3)

	session.Replay(t, "code-scanning/get-suggested-fix-and-annotations.yml")
}

func TestGetSuggestedFixWithAppliedFix(t *testing.T) {
	var repositoryID uint64 = 351
	repositoryEID := ts.RepositoryEID(repositoryID)
	commitA := "a270ea0fdfba2bd5a33934e5184784cddce87f38"
	commitB := "480d4f47447129f015cb327536c522ca683939a1"
	ref := "refs/pull/42/merge"

	session := cassettes.NewSession(t)
	session.Analyze(t, repositoryID, "../../cocofix/testdata/reflected-xss.sarif", ".github/workflows/codeql.yml:CodeQL", ref, cassettes.WithCommitOid(commitA))

	// Generate suggested fix
	description := "To fix this vulnerability, we need to sanitize the user input before incorporating it into the response. We can use the `escape-html` library to escape any potentially harmful characters in the user input.\n\nThe best way to fix the vulnerability without changing existing functionality is to add an import for the `escape-html` library at the top of the file and then use the `escape` function to sanitize the `req.query.name` before incorporating it into the response.\n\nHere's what needs to be changed in the index.js file:\n\n1. Add an import for the `escape-html` library at the top of the file.\n2. Replace the line that incorporates the user input into the response with a sanitized version of the input.\n"

	fileDiffs := [][]byte{
		[]byte("--- a/index.js\n+++ b/index.js\n@@ -1 +1,2 @@\n+const escape = require('escape-html');\n const express = require('express');\n@@ -3,2 +4,2 @@\n const app = express();\n-app.get('/', (req, res) => res.send(`Hello, ${req.query.name}!`));\n\\ No newline at end of file\n+app.get('/', (req, res) => res.send(`Hello, ${escape(req.query.name)}!`));\n\\ No newline at end of file\n"),
		[]byte("--- a/package.json\n+++ b/package.json\n@@ -9,3 +9,4 @@\n   \"dependencies\": {\n-    \"express\": \"^4.17.1\"\n+    \"express\": \"^4.17.1\",\n+    \"escape-html\": \"^1.0.3\"\n   },\n"),
	}

	session.CreateSuggestedFix(t, repositoryEID, 1, 1, description, fileDiffs, commitA, ref, nil)

	// Suggested fix is applied
	session.Replay(t, "code-scanning/apply-suggested-fix.yml")
	session.MockSuggestedFixFile(t, "index.js", commitB, []byte("content is changed after applying fix"))
	session.MockSuggestedFixFile(t, "package.json", commitB, []byte("content is changed after applying fix"))

	// Alert is fixed
	session.Analyze(t, repositoryID, "./data/empty.sarif", ".github/workflows/codeql.yml:CodeQL", ref, cassettes.WithCommitOid(commitB))

	// Get applied suggested fix
	session.Replay(t, "code-scanning/get-applied-suggested-fix.yml")
	session.Replay(t, "code-scanning/get-applied-suggested-fix-and-annotations.yml")
}

func TestGetSuggestedFixWithOnlyIndeterminateAlerts(t *testing.T) {
	session := cassettes.NewSession(t)

	session.Replay(t, "code-scanning/get-suggested-fix-with-only-indeterminate-alerts.yml")
}

func TestNewAlertWithASuggestedFix(t *testing.T) {
	var repositoryID uint64 = 351
	repositoryEID := ts.RepositoryEID(repositoryID)
	commitA := "a270ea0fdfba2bd5a33934e5184784cddce87f38"
	commitB := "480d4f47447129f015cb327536c522ca683939a1"

	session := cassettes.NewSession(t)
	session.Analyze(t, repositoryID, "./data/empty.sarif", "a", "refs/heads/main", cassettes.WithCommitOid(commitA))
	session.Analyze(t, repositoryID, "../../cocofix/testdata/reflected-xss.sarif", "a", "refs/pull/42/merge", cassettes.WithCommitOid(commitB))

	session.Replay(t, "code-scanning/reflected-xss-pr-alerts.yml")
	session.Replay(t, "code-scanning/pr-introduced-alerts.yml")

	description := "To fix this vulnerability, we need to sanitize the user input before incorporating it into the response. We can use the `escape-html` library to escape any potentially harmful characters in the user input.\n\nThe best way to fix the vulnerability without changing existing functionality is to add an import for the `escape-html` library at the top of the file and then use the `escape` function to sanitize the `req.query.name` before incorporating it into the response.\n\nHere's what needs to be changed in the index.js file:\n\n1. Add an import for the `escape-html` library at the top of the file.\n2. Replace the line that incorporates the user input into the response with a sanitized version of the input."

	indexJSDiff, err := os.ReadFile("./data/reflected-xss-indexjs.diff")
	require.NoError(t, err)

	packageJSONDiff, err := os.ReadFile("./data/reflected-xss-packagejson.diff")
	require.NoError(t, err)

	fileDiffs := [][]byte{
		indexJSDiff,
		packageJSONDiff,
	}

	dependencyMetadata := ts.SuggestedFixDependencyMetadata{
		ts.SuggestedFixDependency{
			Name:       "escape-html",
			Version:    "1.0.3",
			Advisories: []ts.SuggestedFixAdvisory{},
			Url:        "https://www.npmjs.com/package/escape-html",
			Ecosystem:  "npm",
		},
		ts.SuggestedFixDependency{
			Name:    "lodash",
			Version: "4.17.21",
			Advisories: []ts.SuggestedFixAdvisory{
				{
					Id:          "123-456",
					HtmlUrl:     "http://example.org",
					Summmary:    "test summary",
					Description: "test vuln",
					Severity:    ts.SuggestedFixAdvisorySeverity_HIGH,
				},
			},
			Url:       "https://www.npmjs.com/package/lodash",
			Ecosystem: "npm",
		},
	}

	session.CreateSuggestedFix(t, repositoryEID, 1, 1, description, fileDiffs, commitB, "refs/pull/42/merge", dependencyMetadata)

	session.Replay(t, "code-scanning/reflected-xss-suggested-fix.yml")

	// File in suggested fix (package.json) is changed in new commit
	commitC := "c9b9ef15dd2f157f7fe616620251bd0834ed1e5f"
	session.MockSuggestedFixFile(t, "index.js", commitC, []byte("some content"))
	session.MockSuggestedFixFile(t, "package.json", commitC, []byte("content is changed after applying fix"))
	session.Replay(t, "code-scanning/outdated-suggested-fix.yml")

	session.Replay(t, "code-scanning/pr-introduced-alerts-with-autofix.yml")
}

func TestGenerateSuggestedFix_RuleNotSupported(t *testing.T) {
	var repositoryID uint64 = 351
	commitA := "a270ea0fdfba2bd5a33934e5184784cddce87f38"
	ref := "refs/pull/42/merge"

	session := cassettes.NewSession(t)
	session.Analyze(t, repositoryID, "./data/3-warnings-1-note.sarif", ".github/workflows/w1.yml:job1", ref, cassettes.WithCommitOid(commitA))

	session.Replay(t, "code-scanning/suggested-fix-rule-not-supported.yml")
}

func TestGenerateSuggestedFix_Thirdparty(t *testing.T) {
	var repositoryID uint64 = 351
	repositoryEID := ts.RepositoryEID(repositoryID)
	commitA := "a270ea0fdfba2bd5a33934e5184784cddce87f38"
	ref := "refs/pull/42/merge"

	session := cassettes.NewSession(t)
	session.Analyze(t, repositoryID, "./data/other.sarif", ".github/workflows/w1.yml:job1", ref, cassettes.WithCommitOid(commitA))

	description1 := "We have a suggestion to fix this alert.\n"

	fileDiffs := [][]byte{
		[]byte("--- a/file.js\n+++ b/file.js\n@@ -10,2 +10,2 @@\n \tconst one = 1\n-\tconst two = 4\n+\tconst two = 2\n"),
	}

	session.CreateSuggestedFix(t, repositoryEID, 1, 1, description1, fileDiffs, commitA, ref, nil)

	session.Replay(t, "code-scanning/get-suggested-fix-and-annotations-thirdparty.yml")
}

func TestGetSuggestedFixStatesForOrg(t *testing.T) {
	var repo1 uint64 = 351
	var repo2 uint64 = 300
	var repo3 uint64 = 404
	var orgId uint64 = 71

	repo1EID := ts.RepositoryEID(repo1)
	repo2EID := ts.RepositoryEID(repo2)
	commit1 := "a270ea0fdfba2bd5a33934e5184784cddce87f38"
	commit2 := "480d4f47447129f015cb327536c522ca683939a1"
	commit3 := "c9b9ef15dd2f157f7fe616620251bd0834ed1e5f"
	ref := "refs/heads/main"

	session := cassettes.NewSessionWithES(t)
	session.Analyze(t, repo1, "../../cocofix/testdata/reflected-xss.sarif", "a", ref, cassettes.WithCommitOid(commit1))
	session.Analyze(t, repo1, "../../cocofix/testdata/made-up-alert.sarif", "b", ref, cassettes.WithCommitOid(commit1))
	session.Analyze(t, repo1, "./data/3-warnings-1-note.sarif", "c", ref, cassettes.WithCommitOid(commit1))
	session.Analyze(t, repo1, "./data/3alerts.sarif", "d", ref, cassettes.WithCommitOid(commit1))
	session.Analyze(t, repo2, "./data/3alerts.sarif", "a", ref, cassettes.WithCommitOid(commit2))
	session.Analyze(t, repo3, "./data/3alerts.sarif", "a", ref, cassettes.WithCommitOid(commit3))

	description := "To fix this vulnerability, we need to sanitize the user input before incorporating it into the response. We can use the `escape-html` library to escape any potentially harmful characters in the user input.\n\nThe best way to fix the vulnerability without changing existing functionality is to add an import for the `escape-html` library at the top of the file and then use the `escape` function to sanitize the `req.query.name` before incorporating it into the response.\n\nHere's what needs to be changed in the index.js file:\n\n1. Add an import for the `escape-html` library at the top of the file.\n2. Replace the line that incorporates the user input into the response with a sanitized version of the input.\n"

	fileDiffs := [][]byte{
		[]byte("--- a/index.js\n+++ b/index.js\n@@ -1 +1,2 @@\n+const escape = require('escape-html');\n const express = require('express');\n@@ -3,2 +4,2 @@\n const app = express();\n-app.get('/', (req, res) => res.send(`Hello, ${req.query.name}!`));\n\\ No newline at end of file\n+app.get('/', (req, res) => res.send(`Hello, ${escape(req.query.name)}!`));\n\\ No newline at end of file\n"),
		[]byte("--- a/package.json\n+++ b/package.json\n@@ -9,3 +9,4 @@\n   \"dependencies\": {\n-    \"express\": \"^4.17.1\"\n+    \"express\": \"^4.17.1\",\n+    \"escape-html\": \"^1.0.3\"\n   },\n"),
	}

	session.CreateSuggestedFix(t, repo1EID, 1, 1, description, fileDiffs, commit1, ref, nil)
	session.CreateSuggestedFix(t, repo1EID, 2, 2, description, fileDiffs, commit1, ref, nil)
	session.CreateSuggestedFix(t, repo1EID, 3, 3, description, fileDiffs, commit1, ref, nil)
	session.CreateSuggestedFix(t, repo1EID, 4, 4, description, fileDiffs, commit1, ref, nil)
	session.CreateSuggestedFix(t, repo2EID, 1, 8, description, fileDiffs, commit2, ref, nil)

	session.CreateEmptySuggestedFix(t, repo1EID, 5, 5, ref, ts.SuggestedFixAlertStatePending)
	session.CreateEmptySuggestedFix(t, repo1EID, 7, 7, ref, ts.SuggestedFixAlertStateRuleNotSupported)
	session.CreateEmptySuggestedFix(t, repo2EID, 3, 9, ref, ts.SuggestedFixAlertStatePending)

	// Mark alert 3 as resolved
	session.ResolveAlert(t, repo1EID, 3)

	// Define the content for ts_repositories and update the ES index
	session.IndexWithRepoMetadata(t, repo1, orgId, ref, "public", true)
	session.IndexWithRepoMetadata(t, repo2, orgId, ref, "private", true)
	session.IndexWithRepoMetadata(t, repo3, orgId, ref, "private", false) // Code scanning not enabled

	session.RefreshES(t)

	session.Replay(t, "code-scanning/get-suggested-fix-states-for-org.yml")
	session.Replay(t, "code-scanning/get-suggested-fix-states-for-org-pagination.yml")
}
