package flowfile

import (
	"fmt"
	"testing"

	"github.com/stretchr/testify/assert"

	"github.com/github/launch/pkg/launchconfig"
)

func TestPipelineFileCategory(t *testing.T) {
	egs := []struct {
		path     string
		category PipelineFileCategory
	}{
		{
			path:     "README.md",
			category: NotPipelineFile,
		},
		{
			path:     "main.yml",
			category: PipelineCandidate,
		},
		{
			path:     "x.yaml",
			category: PipelineCandidate,
		},
		{
			path:     "yaml",
			category: NotPipelineFile,
		},
		{
			path:     "foo.yml.json",
			category: NotPipelineFile,
		},
		{
			path:     "x.lib.yml",
			category: PipelineCandidate,
		},
		// Examples from https://github.com/github/c2c-actions-support/issues/940
		{
			path:     "x.zyml",
			category: NotPipelineFile,
		},
		{
			path:     "x.zyaml",
			category: NotPipelineFile,
		},
		{
			path:     "x.meyml",
			category: NotPipelineFile,
		},
	}

	for _, eg := range egs {
		t.Run(fmt.Sprintf("categorising `%s`", eg.path), func(t *testing.T) {
			assert.Equal(t, CategoriseCandidatePipelineFileName(eg.path), eg.category)
		})
	}
}

func TestPipelineDirectoryForEnvironment(t *testing.T) {
	egs := []struct {
		path   string
		inPath bool
	}{
		{
			path:   ".github/workflows/some.yml",
			inPath: true,
		},
		{
			path:   ".github/workflows-labs/some.yml",
			inPath: false,
		},
		{
			path:   "some.yaml",
			inPath: false,
		},
		{
			path:   ".github/yaml",
			inPath: false,
		},
	}

	for _, eg := range egs {
		t.Run(fmt.Sprintf("example `%s`", eg.path), func(t *testing.T) {
			assert.Equal(t, InEnvWorkflowDirectory(eg.path, launchconfig.ProductionAppEnv), eg.inPath)
		})
	}
}
