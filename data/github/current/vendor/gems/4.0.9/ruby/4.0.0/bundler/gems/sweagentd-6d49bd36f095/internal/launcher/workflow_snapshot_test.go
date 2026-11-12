package launcher

import (
	"bufio"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestSnapshotWorkflowsAreValid validates that all snapshot workflow files pass
// parser validation. This ensures that our generated workflows are valid
// according to the actions-workflow-parser library.
func TestSnapshotWorkflowsAreValid(t *testing.T) {
	snapshotsDir := "testdata/snapshots"

	// Read all snapshot files
	entries, err := os.ReadDir(snapshotsDir)
	require.NoError(t, err, "failed to read snapshots directory")

	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}

		name := entry.Name()
		if filepath.Ext(name) != ".yaml" && filepath.Ext(name) != ".yml" {
			continue
		}

		t.Run(name, func(t *testing.T) {
			content, err := os.ReadFile(filepath.Join(snapshotsDir, name))
			require.NoError(t, err, "failed to read snapshot file")

			result := validateWorkflowYAML(string(content))
			if !result.Valid {
				t.Logf("Validation errors for %s:\n%s", name, result.FullError())
			}
			assert.True(t, result.Valid, "snapshot workflow %s should be valid", name)
		})
	}
}

// shaRef matches a 40-character lowercase hex SHA at the end of a uses reference.
var shaRef = regexp.MustCompile(`^[a-f0-9]{40}$`)

// usesRef matches the action reference portion of a `uses:` directive (e.g.
// "actions/checkout@v4" or "actions/upload-artifact@abc123...").
var usesRef = regexp.MustCompile(`uses:\s+(\S+)`)

// assertActionsPinnedToSHA scans the given YAML content and asserts that every
// `uses:` directive references a specific commit SHA rather than a mutable tag
// or branch.  Lines that are Go template directives (starting with `<<`) are
// skipped because they are not literal action references.
func assertActionsPinnedToSHA(t *testing.T, filename, content string) {
	t.Helper()

	scanner := bufio.NewScanner(strings.NewReader(content))
	lineNum := 0
	for scanner.Scan() {
		lineNum++
		line := strings.TrimSpace(scanner.Text())

		// Skip Go-template directives that are not real YAML.
		if strings.HasPrefix(line, "<<") {
			continue
		}

		match := usesRef.FindStringSubmatch(line)
		if match == nil {
			continue
		}

		ref := match[1]
		// Docker and local path references (e.g. "docker://..." or "./path")
		// don't need SHA pinning.
		if strings.HasPrefix(ref, "docker://") || strings.HasPrefix(ref, "./") {
			continue
		}

		parts := strings.SplitN(ref, "@", 2)
		require.Len(t, parts, 2, "%s:%d: uses reference %q is missing an @ version", filename, lineNum, ref)

		version := parts[1]
		assert.Truef(t, shaRef.MatchString(version),
			"%s:%d: action %q should be pinned to a specific commit SHA, but got %q",
			filename, lineNum, parts[0], version)
	}
}

// TestWorkflowTemplateActionsPinnedToSHA verifies that every `uses:` directive
// in the workflow template (actions_workflow.yaml) is pinned to a full commit
// SHA rather than a mutable tag or branch name.
func TestWorkflowTemplateActionsPinnedToSHA(t *testing.T) {
	content, err := os.ReadFile("actions_workflow.yaml")
	require.NoError(t, err, "failed to read actions_workflow.yaml")

	assertActionsPinnedToSHA(t, "actions_workflow.yaml", string(content))
}

// TestSnapshotWorkflowActionsPinnedToSHA verifies that every generated snapshot
// workflow has its `uses:` directives pinned to specific commit SHAs.
func TestSnapshotWorkflowActionsPinnedToSHA(t *testing.T) {
	snapshotsDir := "testdata/snapshots"

	entries, err := os.ReadDir(snapshotsDir)
	require.NoError(t, err, "failed to read snapshots directory")

	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}

		name := entry.Name()
		if filepath.Ext(name) != ".yaml" && filepath.Ext(name) != ".yml" {
			continue
		}

		t.Run(name, func(t *testing.T) {
			path := filepath.Join(snapshotsDir, name)
			content, err := os.ReadFile(path)
			require.NoError(t, err, "failed to read snapshot file")

			assertActionsPinnedToSHA(t, name, string(content))
		})
	}
}
