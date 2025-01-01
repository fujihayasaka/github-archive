package sessions

import (
	"testing"

	"github.com/github/turboscan/ts/cassettes"
)

func TestGetExtractedFilesWithMixedSublanguage(t *testing.T) {
	var repositoryID uint64 = 351

	session := cassettes.NewSession(t)

	session.ReplayReadOnly(t, "code-scanning/get-extracted-files-no-summary.yml")

	session.Analyze(
		t,
		repositoryID,
		"../../sarif/testdata/tool-status-notification-with-all-files-extracted.sarif",
		".github/workflows/w1.yml:job1",
		"refs/heads/master",
		cassettes.WithTrackStatus(),
	)

	session.Analyze(
		t,
		repositoryID,
		"../../sarif/testdata/tool-status-notification-with-sublanguage-file-coverage.sarif",
		".github/workflows/w1.yml:job2",
		"refs/heads/master",
		cassettes.WithTrackStatus(),
	)

	session.Replay(t, "code-scanning/get-extracted-files-summary-sublanguage-mixed.yml")
}
