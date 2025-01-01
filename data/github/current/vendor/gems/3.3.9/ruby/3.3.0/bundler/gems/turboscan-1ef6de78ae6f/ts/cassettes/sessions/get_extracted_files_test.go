package sessions

import (
	"testing"

	"github.com/github/turboscan/ts/cassettes"
)

func TestGetExtractedFilesWithBaselineFullyExtracted(t *testing.T) {
	var repositoryID uint64 = 351

	session := cassettes.NewSession(t)

	session.Analyze(
		t,
		repositoryID,
		"../../sarif/testdata/tool-status-notification-with-all-files-extracted.sarif",
		".github/workflows/w1.yml:job1",
		"refs/heads/master",
		cassettes.WithTrackStatus(),
	)

	session.Replay(t, "code-scanning/get-extracted-files-with-baseline-fully-extracted.yml")
}

func TestGetExtractedFilesWithMessages(t *testing.T) {
	var repositoryID uint64 = 351

	session := cassettes.NewSession(t)
	session.Analyze(
		t,
		repositoryID,
		"../../sarif/testdata/tool-status-notification-with-files-not-extracted-messages.sarif",
		".github/workflows/w1.yml:job1",
		"refs/heads/master",
		cassettes.WithTrackStatus(),
	)

	session.Replay(t, "code-scanning/get-extracted-files-with-messages.yml")
}
