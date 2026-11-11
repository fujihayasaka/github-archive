package launcher

import (
	"os"
	"path/filepath"
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
