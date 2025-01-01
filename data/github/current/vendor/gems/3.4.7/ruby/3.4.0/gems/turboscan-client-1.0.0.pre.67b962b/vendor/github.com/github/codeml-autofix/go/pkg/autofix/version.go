package autofix

import (
	"encoding/json"
	"log"
	"runtime/debug"

	// embed allows embedding files.
	_ "embed"
)

// Version encapsulates version information from package.json and the Git commit.
type Version struct {
	AutofixVersion string `json:"autofixVersion"`
}

// dynamically fetches the commit hash of the latest commit.
func CommitHash() string {
	info, ok := debug.ReadBuildInfo()
	if !ok {
		log.Fatalf("Failed to get build info")
	}

	commitHash := "unknown_sha"
	for _, s := range info.Settings {
		if s.Key == "vcs.revision" {
			commitHash = s.Value
		}
	}

	// Optionally, shorten the hash.
	if len(commitHash) > 7 {
		commitHash = commitHash[:7]
	}
	return commitHash
}

//go:embed version.json
var versionData []byte

// CurrentVersion holds the version information for the build.
var CurrentVersion string

func init() {
	var version Version
	if err := json.Unmarshal(versionData, &version); err != nil {
		log.Fatalf("Failed to unmarshal version data: %v", err)
	}
	CurrentVersion = version.AutofixVersion
}
