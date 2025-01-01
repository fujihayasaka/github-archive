package flowfile

import (
	"fmt"
	"regexp"
	"strings"

	"github.com/github/launch/pkg/launchconfig"
)

// directory containing pipeline files, e.g .github/workflows/workflow.yml
const ProdPipelinesDirectory = ".github/workflows"
const LabPipelinesDirectory = ".github/workflows-lab"

type PipelineFileCategory int

const (
	NotPipelineFile = iota
	PipelineCandidate
	PipelineIncludeCandidate
)

var pipelineFileRe = regexp.MustCompile(`\.ya?ml$`)

// note: only files within `.github/workflows{-lab,}` should be passed
// here, depending on environment
func CategoriseCandidatePipelineFileName(p string) PipelineFileCategory {
	switch {
	case pipelineFileRe.MatchString(p):
		return PipelineCandidate
	default:
		return NotPipelineFile
	}
}

func InEnvWorkflowDirectory(path string, env launchconfig.AppEnv) bool {
	pref := fmt.Sprintf("%s/", PipelineDirectoryForEnvironment(env))
	return strings.HasPrefix(path, pref)
}

func PipelineDirectoryForEnvironment(env launchconfig.AppEnv) string {
	if env == launchconfig.LabAppEnv {
		return LabPipelinesDirectory
	}
	return ProdPipelinesDirectory
}
