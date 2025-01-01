package workflowinvoker

import (
	"context"
	"strings"

	"github.com/github/launch/clients/ghtwirp"
	ghclient "github.com/github/launch/clients/github"
	"github.com/github/launch/flow/flowevents"
	"github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/types"
	"github.com/github/launch/workflowparser"
)

// We use run service for all repos in these orgs
var runServiceEnabledOrgs = map[string]bool{
	// bbq-beets-four-nines is where we tend to test stuff with 99.99% uptime
	"bbq-beets-four-nines": true,
}

// List of repositories that should never use run service
var noRunServiceRepos = []string{
	"bbq-beets/actions-canary",
}

func isNoRunServiceRepo(repo types.RepositoryFullName) bool {
	for _, noRunRepo := range noRunServiceRepos {
		if strings.EqualFold(repo.String(), noRunRepo) {
			return true
		}
	}
	return false
}

func useRunService(
	ctx context.Context,
	parsedWorkflow *workflowparser.Workflow,
	planSKU string,
	repo types.RepositoryFullName,
	repoGlobalID types.GlobalID,
	rootWorkflow *types.ResolvedFile,
	featureEnabledForRepoOrOwners func(ctx context.Context, flag string, repoGlobalID types.GlobalID) bool,
) bool {

	// We need a workflow, this shouldn't really happen
	if rootWorkflow == nil {
		return false
	}

	// Don't allow in enterprise and multi tenant unless actions_enable_run_service_proxima is enabled
	// proxima repos still need to flag in actions_launch_run_service to redirect to run-service
	if !launchconfig.FourNinesAvailable(featureEnabledForRepoOrOwners(ctx, ghclient.RunServiceProximaFeatureFlag, repoGlobalID)) {
		return false
	}

	// Don't allow in certain repos
	if isNoRunServiceRepo(repo) {
		return false
	}

	// Allow runs from in hard-coded owners
	if _, ok := runServiceEnabledOrgs[repo.Owner]; ok {
		return true
	}

	// Allow flagged in owners/repos
	if featureEnabledForRepoOrOwners(ctx, ghclient.RunServiceFeatureFlag, repoGlobalID) {
		return true
	}

	if (planSKU == ghtwirp.FreePlan || planSKU == ghtwirp.FreeOrganizationPlan) && featureEnabledForRepoOrOwners(ctx, ghclient.RunServiceFeatureFlagForFreePlans, repoGlobalID) {
		return true
	}

	// Allow Dependabot or pages dynamic workflows if the repo is flagged in
	appName, _, isDynamic := flowevents.ExtractDynamicWorkflowFilePath(rootWorkflow.Path)
	if isDynamic && appName == "dependabot" {
		return featureEnabledForRepoOrOwners(ctx, ghclient.RunServiceDependabotFlag, repoGlobalID)
	}
	if isDynamic && appName == "pages" {
		return featureEnabledForRepoOrOwners(ctx, ghclient.RunServicePagesFlag, repoGlobalID) &&
			!featureEnabledForRepoOrOwners(ctx, ghclient.PagesMariner2RunnerLabelFlag, repoGlobalID) &&
			!featureEnabledForRepoOrOwners(ctx, ghclient.PagesSelfHostedRunnerLabelFlag, repoGlobalID)
	}

	// Look at the workflow for an annotation, and if found, check if allowed
	if strings.HasPrefix(rootWorkflow.Text, "# run-in-four-nines") {
		return featureEnabledForRepoOrOwners(ctx, ghclient.AllowRunServiceAnnotation, repoGlobalID)
	}

	if parsedWorkflow != nil {
		// Finally, look at parsedWorkflow
		if featureEnabledForRepoOrOwners(ctx, ghclient.RunServiceFeatureFlagForHardCodedHostedLabels, repoGlobalID) {
			return workflowparser.IsUsingHardCodedHostedRunnerLabels(parsedWorkflow)
		}
	}

	return false
}
