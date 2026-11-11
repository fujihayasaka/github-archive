package memoryhttp

// Snapshot tests for the /prompt endpoint.
//
// These tests capture the full MemoryPromptResponse output for each feature-flag
// variation as golden files in testdata/snapshots/. Two formats are stored:
//
//   - .json — exact JSON serialization of the response struct. Catches new or
//     removed fields, changed versions, and structural drift.
//   - .md  — human-readable markdown rendering of the prompt text. Produces
//     clear, reviewable diffs on github.com during PR review.
//
// When prompt text or response structure changes intentionally, update the
// golden files by running:
//
//	go test ./internal/memory/memoryhttp/ -run TestPromptSnapshots -update
//
// Then review the diff and commit the updated snapshots alongside your change.

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/github/sweagentd/internal/memory/core"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

var update = flag.Bool("update", false, "update snapshot golden files")

// sampleMemories returns a deterministic set of memories used across all snapshot tests
// that include memories. These match the test fixtures in memory_handler_prompt_test.go.
func sampleMemories() []*core.Memory {
	return []*core.Memory{
		{
			ID:        core.MemoryID("mem1"),
			Subject:   "testing practices",
			Fact:      "Use vitest for unit tests",
			Citations: []string{"vitest.config.ts:5"},
		},
		{
			ID:        core.MemoryID("mem2"),
			Subject:   "code style",
			Fact:      "Use single quotes for strings",
			Citations: []string{"eslintrc.json:10", ".prettierrc:3"},
		},
		{
			ID:        core.MemoryID("mem3"),
			Subject:   "build commands",
			Fact:      "Run npm run build to build the project",
			Citations: []string{},
		},
	}
}

// escapeHTMLTags replaces angle brackets so XML-style prompt tags (e.g. <examples>)
// render visibly in GitHub markdown instead of being swallowed as HTML.
func escapeHTMLTags(s string) string {
	return strings.NewReplacer("<", "&lt;", ">", "&gt;").Replace(s)
}

// formatSnapshotMarkdown renders a MemoryPromptResponse as human-readable markdown.
// The output is designed to produce clear diffs on github.com during PR review.
func formatSnapshotMarkdown(resp MemoryPromptResponse) string {
	parts := []string{
		"# Metadata",
		"",
		"| Field | Value |",
		"|-------|-------|",
		fmt.Sprintf("| Store Instructions Version | %s |", resp.StoreInstructions.PromptVersion),
		fmt.Sprintf("| Memories Context Version | %s |", resp.MemoriesContext.PromptVersion),
		fmt.Sprintf("| Memories Count | %d |", resp.MemoriesContext.MemoriesCount),
	}
	if resp.MemoriesContext.RepoMemoriesCount != nil {
		parts = append(parts, fmt.Sprintf("| Repo Memories Count | %d |", *resp.MemoriesContext.RepoMemoriesCount))
	}
	if resp.MemoriesContext.UserMemoriesCount != nil {
		parts = append(parts, fmt.Sprintf("| User Memories Count | %d |", *resp.MemoriesContext.UserMemoriesCount))
	}
	parts = append(parts,
		"",
		"# Tool Definitions",
		"",
		fmt.Sprintf("## %s (v%s)", resp.StoreToolDefinition.Name, resp.StoreToolDefinition.DefinitionVersion),
		"",
		escapeHTMLTags(resp.StoreToolDefinition.Description),
	)
	if resp.VoteToolDefinition != nil {
		parts = append(parts,
			"",
			fmt.Sprintf("## %s (v%s)", resp.VoteToolDefinition.Name, resp.VoteToolDefinition.DefinitionVersion),
			"",
			escapeHTMLTags(resp.VoteToolDefinition.Description),
		)
	}

	parts = append(parts, "", "# Store Instructions Prompt", "")
	if resp.StoreInstructions.Prompt != "" {
		parts = append(parts, escapeHTMLTags(resp.StoreInstructions.Prompt))
	} else {
		parts = append(parts, "*(empty)*")
	}

	parts = append(parts, "", "# Memories Context Prompt", "")
	if resp.MemoriesContext.Prompt != "" {
		parts = append(parts, escapeHTMLTags(resp.MemoriesContext.Prompt))
	} else {
		parts = append(parts, "*(empty)*")
	}

	return strings.Join(parts, "\n") + "\n"
}

// compareSnapshot compares got against the golden file at snapshotPath.
// When the -update flag is set, it overwrites the golden file instead.
func compareSnapshot(t *testing.T, snapshotPath string, got []byte) {
	t.Helper()

	if *update {
		err := os.WriteFile(snapshotPath, got, 0o644)
		require.NoError(t, err, "failed to update snapshot %s", snapshotPath)
		t.Logf("updated snapshot: %s", snapshotPath)
		return
	}

	expected, err := os.ReadFile(snapshotPath)
	require.NoError(t, err,
		"snapshot file %s not found — run the following to generate:\n\n"+
			"  go test ./internal/memory/memoryhttp/ -run TestPromptSnapshots -update\n",
		snapshotPath)

	assert.Equal(t, string(expected), string(got),
		"snapshot mismatch for %s\n\n"+
			"If this change is intentional, update the golden files by running:\n\n"+
			"  go test ./internal/memory/memoryhttp/ -run TestPromptSnapshots -update\n\n"+
			"Then review the diff and commit the updated snapshots.",
		snapshotPath)
}

func TestPromptSnapshots(t *testing.T) {
	snapshotsDir := "testdata/snapshots"

	tests := []struct {
		name     string
		basename string
		memories []*core.Memory
		opts     []promptOption
	}{
		{
			name:     "voting disabled with memories",
			basename: "voting-disabled-with-memories",
			memories: sampleMemories(),
			opts:     nil,
		},
		{
			name:     "voting enabled with memories",
			basename: "voting-enabled-with-memories",
			memories: sampleMemories(),
			opts:     []promptOption{withVoting(true)},
		},
		{
			name:     "voting disabled no memories",
			basename: "voting-disabled-no-memories",
			memories: nil,
			opts:     nil,
		},
		{
			name:     "voting enabled no memories",
			basename: "voting-enabled-no-memories",
			memories: nil,
			opts:     []promptOption{withVoting(true)},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			response, err := newPromptBuilder(tt.memories, tt.opts...).buildResponse()
			require.NoError(t, err)

			t.Run("json", func(t *testing.T) {
				got, err := json.MarshalIndent(response, "", "  ")
				require.NoError(t, err)
				compareSnapshot(t, filepath.Join(snapshotsDir, tt.basename+".json"), got)
			})

			t.Run("markdown", func(t *testing.T) {
				got := formatSnapshotMarkdown(response)
				compareSnapshot(t, filepath.Join(snapshotsDir, tt.basename+".md"), []byte(got))
			})
		})
	}
}

// sampleCombinedRepoMemories returns deterministic repo-scoped memories for combined snapshot tests.
func sampleCombinedRepoMemories() []*core.Memory {
	return []*core.Memory{
		{
			ID:        core.MemoryID("repo1"),
			Subject:   "testing practices",
			Fact:      "Use vitest for unit tests",
			Citations: []string{"vitest.config.ts:5"},
		},
		{
			ID:        core.MemoryID("repo2"),
			Subject:   "code style",
			Fact:      "Use single quotes for strings",
			Citations: []string{"eslintrc.json:10", ".prettierrc:3"},
		},
	}
}

// sampleCombinedUserMemories returns deterministic user-scoped memories for combined snapshot tests.
func sampleCombinedUserMemories() []*core.Memory {
	return []*core.Memory{
		{
			ID:        core.MemoryID("user1"),
			Subject:   "editor config",
			Fact:      "Prefer dark theme for all editors",
			Citations: []string{},
		},
	}
}

var snapshotRepoNWO = &core.RepoNWO{Owner: "octocat", Repo: "hello-world"}

func TestCombinedPromptSnapshots(t *testing.T) {
	snapshotsDir := "testdata/snapshots"

	tests := []struct {
		name         string
		basename     string
		repoMemories []*core.Memory
		userMemories []*core.Memory
		repoNWO      *core.RepoNWO
		opts         []promptOption
	}{
		{
			name:         "with no memories",
			basename:     "combined-no-memories",
			repoMemories: nil,
			userMemories: nil,
			repoNWO:      snapshotRepoNWO,
			opts:         []promptOption{withUserScoped(true), withVoting(true)},
		},
		{
			name:         "with only repo memories",
			basename:     "combined-only-repo-memories",
			repoMemories: sampleCombinedRepoMemories(),
			userMemories: nil,
			repoNWO:      snapshotRepoNWO,
			opts:         []promptOption{withUserScoped(true), withVoting(true)},
		},
		{
			name:         "with only user memories",
			basename:     "combined-only-user-memories",
			repoMemories: nil,
			userMemories: sampleCombinedUserMemories(),
			repoNWO:      nil,
			opts:         []promptOption{withUserScoped(true), withVoting(true)},
		},
		{
			name:         "with user and repo memories",
			basename:     "combined-user-and-repo-memories",
			repoMemories: sampleCombinedRepoMemories(),
			userMemories: sampleCombinedUserMemories(),
			repoNWO:      snapshotRepoNWO,
			opts:         []promptOption{withUserScoped(true), withVoting(true)},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			response, err := newCombinedPromptBuilder(tt.repoMemories, tt.userMemories, tt.repoNWO, "octocat", tt.opts...).buildResponse()
			require.NoError(t, err)

			// NOTE: totalRepositoryMemoriesCount is always 0 in snapshots because the builder
			// doesn't know the true total — that comes from a separate count query in the handler
			// which overwrites this field with the real value from Cosmos at request time.

			t.Run("json", func(t *testing.T) {
				got, err := json.MarshalIndent(response, "", "  ")
				require.NoError(t, err)
				compareSnapshot(t, filepath.Join(snapshotsDir, tt.basename+".json"), got)
			})

			t.Run("markdown", func(t *testing.T) {
				got := formatSnapshotMarkdown(response)
				compareSnapshot(t, filepath.Join(snapshotsDir, tt.basename+".md"), []byte(got))
			})
		})
	}
}
