package wfparser

import (
	"context"
	"testing"

	parser "github.com/github/actions-workflow-parser/go"
	"github.com/stretchr/testify/require"

	"github.com/github/launch/observability"
)

func TestFileProvider_GetFileContents(t *testing.T) {
	testCases := []struct {
		name          string
		files         []WorkflowReferencedFile
		allowReusable bool
		pathWanted    string
		resultWanted  string
		errWanted     error
	}{
		{
			name: "works for a simple workflow",
			files: []WorkflowReferencedFile{
				{
					Path: ".github/workflows/file.yaml",
					Text: "simple workflow contents",
				},
			},
			pathWanted:   ".github/workflows/file.yaml",
			resultWanted: "simple workflow contents",
		},
		{
			name: "allows dynamic workflow from Dependabot",
			files: []WorkflowReferencedFile{
				{
					Path: "dynamic/dependabot/dependabot-workflow.yaml",
					Text: "dependabot workflow contents",
				},
			},
			pathWanted:   "dynamic/dependabot/dependabot-workflow.yaml",
			resultWanted: "dependabot workflow contents",
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			fp := NewFileProvider(context.Background(), observability.NewNullObservability(), tc.files)
			result, err := fp.GetFileContents(tc.pathWanted)
			require.Equal(t, tc.errWanted, err)
			require.Equal(t, tc.resultWanted, result)
		})
	}
}

func TestFileProvider_GetFileInfo(t *testing.T) {
	testCases := []struct {
		name          string
		files         []WorkflowReferencedFile
		allowReusable bool
		path          string
		resultWanted  *parser.FileInfo
		errWanted     error
	}{
		{
			name: "works for a simple workflow",
			files: []WorkflowReferencedFile{
				{
					Path:          ".github/workflows/file.yaml",
					Text:          "simple workflow contents",
					SHA:           "abc123",
					RepositoryNwo: "monalisa/octocat",
				},
			},
			path: ".github/workflows/file.yaml",
			resultWanted: &parser.FileInfo{
				Path:        ".github/workflows/file.yaml",
				NWO:         "monalisa/octocat",
				ResolvedSHA: "abc123",
			},
		},
		{
			name: "allows dynamic workflow from Dependabot",
			files: []WorkflowReferencedFile{
				{
					Path:          "dynamic/dependabot/dependabot-workflow.yaml",
					Text:          "dependabot workflow contents",
					RepositoryNwo: "",
					SHA:           "",
				},
			},
			path: "dynamic/dependabot/dependabot-workflow.yaml",
			resultWanted: &parser.FileInfo{
				Path: "dynamic/dependabot/dependabot-workflow.yaml",
			},
		},
		{
			name: "works for a required workflow",
			files: []WorkflowReferencedFile{
				{
					Path:          ".github/workflows/file.yaml",
					Text:          "required workflow contents",
					SHA:           "abc123",
					RepositoryNwo: "monalisa/octocat",
					IsRequired:    true,
				},
			},
			path: ".github/workflows/file.yaml",
			resultWanted: &parser.FileInfo{
				Path:        ".github/workflows/file.yaml",
				NWO:         "monalisa/octocat",
				ResolvedSHA: "abc123",
				IsRequired:  true,
			},
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			fp := NewFileProvider(context.Background(), observability.NewNullObservability(), tc.files)
			result, err := fp.GetFileInfo(tc.path)
			require.Equal(t, tc.errWanted, err)
			require.Equal(t, tc.resultWanted, result)
		})
	}
}

func TestFileProvider_pathMatchesFile(t *testing.T) {
	testCases := []struct {
		name     string
		path     string
		file     WorkflowReferencedFile
		result   bool
		hasError bool
	}{
		{
			name: "handle bare path, local reusable case",
			path: ".github/workflows/file.yml",
			file: WorkflowReferencedFile{
				Path: ".github/workflows/file.yml",
			},
			result: true,
		},
		{
			name: "handle how required workflows (first beta iteration of them) come through, as bare paths to whatever folder they are in",
			path: "required.yml",
			file: WorkflowReferencedFile{
				Path: "required.yml",
			},
			result: true,
		},
		{
			name: "fully formed path with SHA",
			path: "org/repo/.github/workflows/file.yml@0d2232962e3069c745098008ecceb0b7726088a7",
			file: WorkflowReferencedFile{
				Path: "org/repo/.github/workflows/file.yml@0d2232962e3069c745098008ecceb0b7726088a7",
			},
			result: true,
		},
		{
			name: "allow repo name case differences",
			path: "org/REPO/.github/workflows/file.yml@0d2232962e3069c745098008ecceb0b7726088a7",
			file: WorkflowReferencedFile{
				Path: "org/repo/.github/workflows/file.yml@0d2232962e3069c745098008ecceb0b7726088a7",
			},
			result: true,
		},
		{
			name: "allow repo name case differences other direction",
			path: "org/repo/.github/workflows/file.yml@0d2232962e3069c745098008ecceb0b7726088a7",
			file: WorkflowReferencedFile{
				Path: "org/REPO/.github/workflows/file.yml@0d2232962e3069c745098008ecceb0b7726088a7",
			},
			result: true,
		},
		{
			name: "allow org name case differences",
			path: "ORG/repo/.github/workflows/file.yml@0d2232962e3069c745098008ecceb0b7726088a7",
			file: WorkflowReferencedFile{
				Path: "org/repo/.github/workflows/file.yml@0d2232962e3069c745098008ecceb0b7726088a7",
			},
			result: true,
		},
		{
			name: "allow org name case differences other direction",
			path: "org/repo/.github/workflows/file.yml@0d2232962e3069c745098008ecceb0b7726088a7",
			file: WorkflowReferencedFile{
				Path: "ORG/repo/.github/workflows/file.yml@0d2232962e3069c745098008ecceb0b7726088a7",
			},
			result: true,
		},
		{
			name: "disallow file path or filename case differences",
			path: "org/repo/.github/workflows/file.yml@0d2232962e3069c745098008ecceb0b7726088a7",
			file: WorkflowReferencedFile{
				Path: "org/REPO/.github/workflows/FILE.yml@0d2232962e3069c745098008ecceb0b7726088a7",
			},
			result: false,
		},
		{
			name: "invalid path returns an error",
			path: "org/repo",
			file: WorkflowReferencedFile{
				Path: "org/REPO/.github/workflows/FILE.yml@0d2232962e3069c745098008ecceb0b7726088a7",
			},
			result:   false,
			hasError: true,
		},
		{
			name: "invalid file.Path returns an error",
			path: "org/repo/.github/workflows/file.yml@0d2232962e3069c745098008ecceb0b7726088a7",
			file: WorkflowReferencedFile{
				Path: "org/repo",
			},
			result:   false,
			hasError: true,
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			res, err := pathMatchesFile(tc.path, tc.file)
			if tc.hasError {
				require.Error(t, err)
			} else {
				require.NoError(t, err)
			}
			require.Equal(t, tc.result, res)
		})
	}
}
