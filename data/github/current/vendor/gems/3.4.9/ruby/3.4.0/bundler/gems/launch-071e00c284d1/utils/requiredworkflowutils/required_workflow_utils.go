package requiredworkflowutils

import (
	"fmt"
	"strconv"
	"strings"

	"github.com/pkg/errors"

	"github.com/github/launch/flow/flowevents"
)

// These are the list of events that will trigger running a workflow specified in a ruleset
var workflowRuleAllowedEvents = map[string]bool{
	flowevents.PullRequest:       true,
	flowevents.PullRequestTarget: true,
	flowevents.MergeGroup:        true,
}

const (
	// We include the required workflow blob's source repoID in the path to easily
	// identify required workflows across the code without any conflicts
	requiredWorkflowsPathPrefixFormat = "required/%d/%s"

	// The path prefix for required workflows
	requiredWorkflowsPathPrefix = "required/"
)

// ExtractAndRemoveMetadataFromRequiredWorkflowPath extracts source repoID and
// and returns the workflow path without any metadata
func ExtractAndRemoveMetadataFromRequiredWorkflowPath(path string) (int64, string, error) {
	if !IsRequiredWorkflow(path) {
		return 0, path, nil
	}

	requiredWorkflowPathList := strings.Split(path, "/")
	if len(requiredWorkflowPathList) < 3 {
		return 0, "", fmt.Errorf("could not find enough information in path %s to resolve source repoID", path)
	}

	repoID, err := strconv.ParseInt(requiredWorkflowPathList[1], 10, 64)
	if err != nil {
		return 0, "", errors.Wrap(err, "could not parse source repoID")
	}

	return repoID, strings.Join(requiredWorkflowPathList[2:], "/"), err
}

// Constructs the required workflow path by adding the `required` prefix
// and the source repo metadata
func ConstructRequiredWorkflowPath(path string, sourceRepoID int64) string {
	return fmt.Sprintf(requiredWorkflowsPathPrefixFormat,
		sourceRepoID,
		path)
}

func IsRequiredWorkflow(path string) bool {
	return strings.HasPrefix(path, requiredWorkflowsPathPrefix)
}

// RemoveMetadataFromRequiredWorkflowPath extracts and returns the
// workflow path without any metadata
func RemoveMetadataFromRequiredWorkflowPath(path string) string {
	if !IsRequiredWorkflow(path) {
		return path
	}
	requiredWorkflowPathList := strings.Split(path, "/")
	return strings.Join(requiredWorkflowPathList[2:], "/")
}

func IsEventAllowedForWorkflowRulesets(event string) bool {
	isEventAllowedForWorkflowRulesets := false
	_, isEventAllowedForWorkflowRulesets = workflowRuleAllowedEvents[event]

	return isEventAllowedForWorkflowRulesets

}
