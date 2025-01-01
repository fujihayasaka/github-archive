package archive

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestGetResourceFiles(t *testing.T) {
	tempDir := t.TempDir()

	testFiles := []string{
		"issues_000001.json",
		"issues_000002.json",
		"issues_000003.json",
		"organizations_000001.json",
		"organizations_000002.json",
		"users_000001.json",
		"hard_link_src.json",
	}
	for _, file := range testFiles {
		path := filepath.Join(tempDir, file)
		if _, err := os.Create(path); err != nil {
			t.Fatalf("failed to create test file %s: %v", file, err)
		}
	}

	symLinkSrc := filepath.Join(tempDir, "organizations_000001.json")
	symLinkDst := filepath.Join(tempDir, "organizations_000003.json")
	if err := os.Symlink(symLinkSrc, symLinkDst); err != nil {
		t.Fatalf("failed to create symbolic link %s: %v", symLinkDst, err)
	}

	hardLinkSrc := filepath.Join(tempDir, "hard_link_src.json")
	hardLinkDst := filepath.Join(tempDir, "users_000002.json")
	if err := os.Link(hardLinkSrc, hardLinkDst); err != nil {
		t.Fatalf("failed to create hard link %s: %v", hardLinkDst, err)
	}

	tests := []struct {
		description  string
		resourceType string
		expected     []string
	}{
		{
			description:  "returns all files for a given resource type",
			resourceType: "issues",
			expected: []string{
				filepath.Join(tempDir, "issues_000001.json"),
				filepath.Join(tempDir, "issues_000002.json"),
				filepath.Join(tempDir, "issues_000003.json"),
			},
		},
		{
			description:  "ignores symbolic links",
			resourceType: "organizations",
			expected: []string{
				filepath.Join(tempDir, "organizations_000001.json"),
				filepath.Join(tempDir, "organizations_000002.json"),
			},
		},
		{
			description:  "ignores hard links",
			resourceType: "users",
			expected: []string{
				filepath.Join(tempDir, "users_000001.json"),
			},
		},
		{
			description:  "returns empty slice if resource files are not found",
			resourceType: "non_existent",
			expected:     []string{},
		},
	}

	for _, tt := range tests {
		t.Run(tt.description, func(t *testing.T) {
			files, err := getResourceFiles(tempDir, tt.resourceType)

			require.NoError(t, err)
			assert.ElementsMatch(t, tt.expected, files)
		})
	}
}

func Test_extractNumber(t *testing.T) {
	type args struct {
		resourceType string
		filename     string
	}
	tests := []struct {
		name string
		args args
		want int
	}{
		{
			name: "parses number from filename",
			args: args{resourceType: "issues", filename: "issues_000001.json"},
			want: 1,
		},
		{
			name: "parses filename without number",
			args: args{resourceType: "issues", filename: "issues.json"},
			want: 0,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equalf(t, tt.want, extractNumber(tt.args.resourceType, tt.args.filename), "extractNumber(%v, %v)", tt.args.resourceType, tt.args.filename)
		})
	}
}
