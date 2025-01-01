package github

import (
	"fmt"

	"github.com/github/launch/flow/flowfile"
	"github.com/github/launch/types"
)

// pulls in workflow files
const workflowFilesGQLFragment = `pipelinesDirectory:object(expression:$pipelinesDirExpr) {
	... on Tree {
	  entries {
		name
		object {
		  ... on Blob {
			text
			isTruncated
		  }
		}
		workflow {
		  state
		}
	  }
	}
}`

func mapPipelineFiles(entries []treeEntry, dir string, repoGID types.GlobalID, nwo types.RepositoryFullName, sha types.CommitSha) []types.ResolvedFile {
	var pipelineFiles []types.ResolvedFile
	for _, f := range entries {
		// workflow states: https://github.com/github/github/blob/master/lib/platform/enums/workflow_state.rb
		// Workflow could be empty if it is from a PR, so that workflow entity is not yet created
		// DELETED workflows are allowed since users can restore a workflow.
		if flowfile.CategoriseCandidatePipelineFileName(f.Name) == flowfile.PipelineCandidate && (f.Workflow == nil || f.Workflow.State == "ACTIVE" || f.Workflow.State == "DELETED") {
			file := types.ResolvedFile{
				Path:          fmt.Sprintf("%s/%s", dir, f.Name),
				Text:          f.Object.Text,
				SHA:           sha.String(),
				IsTruncated:   f.Object.IsTruncated,
				RepositoryID:  repoGID,
				RepositoryNwo: nwo.String(),
			}

			pipelineFiles = append(pipelineFiles, file)
		}
	}
	return pipelineFiles
}

type treeEntry struct {
	Name   string
	Object struct {
		SHA         string
		Text        string
		IsTruncated bool
	}
	Workflow *Workflow
}

type Workflow struct {
	State string
}

type pipelinesDirResult struct {
	Entries []treeEntry
}
