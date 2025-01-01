package workflowinvoker

import (
	"context"

	"github.com/github/go-kvp"
	"github.com/pkg/errors"

	"github.com/github/launch/types"
)

var supportedReuseEvents = []string{
	"push",
	"pull_request",
	"merge_group",
}

func isSupportedReuseEvent(event string) bool {
	for _, supportedEvent := range supportedReuseEvents {
		if event == supportedEvent {
			return true
		}
	}
	return false
}

// Certain events with the reuse_previous_outcome true key in their YAML file can reuse a previous runs outcome if there are matching tree_ids and the previous outcome was successful (internally called green trees)
// With a matching tree_id, the previous outcome will be cloned/reused on the dotcom side and no new run queued in actions-dotnet
// See https://github.com/github/c2c-actions/blob/main/docs/adrs/5554-green-trees.md for more information
func (i *buildInvoker) reusePreviousOutcomeCheck(ctx context.Context, repoID types.GlobalID, invocationEvent string, workflowPath string, eventSHA types.CommitSha) (types.CommitSha, types.GlobalID) {
	if isSupportedReuseEvent(invocationEvent) {
		i.obs.Debug(ctx, "searching for tree_id and previously successful workflows runs for reuse",
			kvp.String("gh.launch.event.name", invocationEvent),
			kvp.String("gh.launch.workflow.file_path", workflowPath),
			kvp.String("gh.launch.event.commit_sha", string(eventSHA)),
		)
		treeID, reusableCheckSuite, err := i.ghTwirpClient.FindTreeIDAndPreviousWorkflowRunToReuse(ctx, repoID, workflowPath, i.invocation.Event.Name, eventSHA)
		if err != nil {
			i.obs.Report(ctx, errors.Wrap(err, "could not retrieve tree ID and reuse information"))
			return types.CommitShaZeroValue, types.NilGlobalID
		}

		if reusableCheckSuite != nil {
			i.obs.Debug(ctx, "found a previous workflow that can be reused",
				kvp.Int64("gh.check_suite.id", reusableCheckSuite.DatabaseID),
			)
			return treeID, reusableCheckSuite.GlobalID
		}

		i.obs.Debug(ctx, "no previous workflow runs found to reuse",
			kvp.String("gh.launch.tree.id", string(treeID)),
		)
		return treeID, types.NilGlobalID
	}

	return types.CommitShaZeroValue, types.NilGlobalID
}
