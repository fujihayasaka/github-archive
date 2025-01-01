package azp

import (
	"context"
	"strings"
	"time"

	githubgo "github.com/google/go-github/v25/github"

	"github.com/github/go-kvp"

	"github.com/github/launch/clients/authzd"
	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/github"
	"github.com/github/launch/clients/spokesd"
	"github.com/github/launch/flow/flowevents"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/requiredworkflowutils"
	"github.com/github/launch/utils/secureref"
)

type WorkflowProvider interface {
	GetWorkflows(ctx context.Context, invokingEventName string, ghe flowevents.GitHubEvent, data *types.WorkflowInvocationData) []types.ResolvedFile
}

func NewWorkflowProvider(spokesClient spokesd.Client, authzClient authzd.Client, ghTwirpClient ghtwirp.Client, obs *observability.Observability, isEnterprise bool, environment launchconfig.AppEnv) WorkflowProvider {
	return &workflowProvider{
		isEnterprise:              isEnterprise,
		requiredWorkflowsProvider: NewRequiredWorkflowsProvider(spokesClient, authzClient, obs),
		ghTwirpClient:             ghTwirpClient,
		obs:                       obs,
		environment:               environment,
	}
}

type workflowProvider struct {
	isEnterprise              bool
	requiredWorkflowsProvider RequiredWorkflowsProvider
	obs                       *observability.Observability
	ghTwirpClient             ghtwirp.Client
	environment               launchconfig.AppEnv
}

type resolvedAdditionalWorkflowFiles struct {
	rulesetWorkflows []types.ResolvedFile
}

func (w *workflowProvider) GetWorkflows(ctx context.Context, invokingEventName string, ghe flowevents.GitHubEvent, data *types.WorkflowInvocationData) []types.ResolvedFile {
	if dynamicEvent, ok := ghe.(*flowevents.DynamicEvent); ok {
		return []types.ResolvedFile{
			{
				Path:        flowevents.BuildDynamicWorkflowFilePath(dynamicEvent.IntegrationName, dynamicEvent.Slug),
				Text:        dynamicEvent.Workflow,
				SHA:         string(data.References.CheckoutCommit.CommitSHA),
				IsTruncated: false,
			},
		}
	}

	resolvedWorkflowFiles := data.PipelineFiles
	additionalResolvedWorkflowFiles, err := w.getAdditionalWorkflows(ctx, data, invokingEventName, ghe)

	if err != nil {
		w.obs.Error(ctx, "failed to fetch additional workflow files", kvp.Err(err), kvp.String("gh.repo.id", data.RepoGlobalID.String()))
	}

	// Use a bool map (hashset) to deduplicate workflows, using path + repositoryID as the composite key
	resolvedWorkflowFilesSet := make(map[string]bool)
	dedupedResolvedWorkflowFiles := make([]types.ResolvedFile, 0)

	// Add ruleset workflows first so they are first to be kept if there are any conflicts
	for _, workflowFile := range additionalResolvedWorkflowFiles.rulesetWorkflows {
		workflowFilePath := requiredworkflowutils.RemoveMetadataFromRequiredWorkflowPath(workflowFile.Path)
		resolvedWorkflowFilesSet[workflowFilePath+workflowFile.RepositoryID.String()] = true
		dedupedResolvedWorkflowFiles = append(dedupedResolvedWorkflowFiles, workflowFile)
	}

	// Add the pipeline workflows, using the path and current repository id to determine if they were already added from the additional workflows
	for _, workflowFile := range resolvedWorkflowFiles {
		if _, ok := resolvedWorkflowFilesSet[workflowFile.Path+data.RepoGlobalID.String()]; !ok {
			resolvedWorkflowFilesSet[workflowFile.Path+data.RepoGlobalID.String()] = true
			dedupedResolvedWorkflowFiles = append(dedupedResolvedWorkflowFiles, workflowFile)
		}
	}

	return dedupedResolvedWorkflowFiles
}

// getAdditionalWorkflows returns workflows that need to be enforced
// in a repository along with other workflows on demand.
func (w *workflowProvider) getAdditionalWorkflows(ctx context.Context, data *types.WorkflowInvocationData, invokingEventName string, ghe flowevents.GitHubEvent) (resolvedAdditionalWorkflowFiles, error) {
	IsEventAllowedForWorkflowRulesets := requiredworkflowutils.IsEventAllowedForWorkflowRulesets(invokingEventName)

	resolvedAdditionalWorkflowFiles := resolvedAdditionalWorkflowFiles{
		rulesetWorkflows: []types.ResolvedFile{},
	}

	// if the triggering event isn't allowed for rulesets, we don't need to fetch any additional workflows
	if !IsEventAllowedForWorkflowRulesets {
		return resolvedAdditionalWorkflowFiles, nil
	}

	event := ghtwirp.EventReference{
		Type: invokingEventName,
	}

	if invokingEventName == flowevents.PullRequest || invokingEventName == flowevents.PullRequestTarget {
		if pre, ok := ghe.(flowevents.HasPullRequest); ok {
			basePullRequestBranch := pre.GetPullRequest().GetBase()

			fqRef, err := secureref.GetFullyQualifiedSecureRef(ctx, w.obs.Logger, basePullRequestBranch, invokingEventName)
			if err != nil {
				return resolvedAdditionalWorkflowFiles, err
			}

			event.BaseRef = fqRef

			event.BeforeOid = types.CommitSha(basePullRequestBranch.GetSHA())
			event.AfterOid = data.References.CheckoutCommit.CommitSHA
		}
	} else if invokingEventName == flowevents.MergeGroup {
		if mge, ok := ghe.(*githubgo.MergeGroupEvent); ok {
			mergeGroup := mge.GetMergeGroup()

			baseRef := types.GitRef(mergeGroup.GetBaseRef())
			event.BaseRef = baseRef

			event.BeforeOid = types.CommitSha(mergeGroup.GetBaseSHA())
			event.AfterOid = types.CommitSha(mergeGroup.GetHeadSHA())
		}
	}

	startGetWorkflows := time.Now()

	additionalWorkflows, err := w.ghTwirpClient.GetAdditionalWorkflows(ctx, data.RepoDatabaseID, event)

	if err != nil {
		return resolvedAdditionalWorkflowFiles, err
	}
	matchEnvPathLabRulesetWorkflowsEnabled := w.ghTwirpClient.IsFeatureEnabledForRepoOrOwners(ctx, github.MatchEnvPathLabRulesetWorkflows, data.RepoGlobalID)
	additionalWorkflowsForEnvironment := AdditionalWorkflowsForEnvironment(additionalWorkflows.RulesetWorkflows, w.environment, matchEnvPathLabRulesetWorkflowsEnabled)

	if len(additionalWorkflows.RulesetWorkflows) == 0 {
		w.obs.Timing(ctx, "get_additional_workflows.duration", statter.Tags{"event": invokingEventName, "additional_workflows_found": "false"}, time.Since(startGetWorkflows))
		return resolvedAdditionalWorkflowFiles, nil
	}

	w.obs.Timing(ctx, "get_additional_workflows.duration", statter.Tags{"event": invokingEventName, "additional_workflows_found": "true"}, time.Since(startGetWorkflows))

	startResolveWorkflows := time.Now()

	if len(additionalWorkflows.RulesetWorkflows) > 0 {
		rulesetWorkflowFiles := w.requiredWorkflowsProvider.GetRequiredWorkflowFiles(ctx, additionalWorkflowsForEnvironment, invokingEventName, data.RepoDatabaseID, data.Actor.DatabaseID)
		resolvedAdditionalWorkflowFiles.rulesetWorkflows = append(resolvedAdditionalWorkflowFiles.rulesetWorkflows, rulesetWorkflowFiles...)
	}

	w.obs.Counter(ctx, "resolved_ruleset_workflow_files", statter.Tags{"event": invokingEventName}, int64(len(resolvedAdditionalWorkflowFiles.rulesetWorkflows)))

	w.obs.Log(ctx,
		"Resolved required workflow blobs for the current event",
		kvp.Int("gh.launch.ruleset_workflows.resolved_count", len(resolvedAdditionalWorkflowFiles.rulesetWorkflows)),
		kvp.Int("gh.launch.ruleset_workflows.actual_count", len(additionalWorkflows.RulesetWorkflows)),
		kvp.Int("gh.repo.id", int(data.RepoDatabaseID)),
		kvp.String("gh.owner.global_id", data.Owner.GlobalID.String()),
		kvp.String("gh.launch.event.name", invokingEventName),
	)
	w.obs.Timing(ctx, "resolve_required_workflows", nil, time.Since(startResolveWorkflows))

	return resolvedAdditionalWorkflowFiles, nil
}

func AdditionalWorkflowsForEnvironment(additionalWorkflows []*ghtwirp.RequiredWorkflow, environment launchconfig.AppEnv, matchEnvPathLabRulesetWorkflowsEnabled bool) []*ghtwirp.RequiredWorkflow {
	additionalWorkflowsForEnvironment := []*ghtwirp.RequiredWorkflow{}

	if matchEnvPathLabRulesetWorkflowsEnabled {
		prefix := ".github/workflows/"
		if environment.IsLab() {
			prefix = ".github/workflows-lab/"
		}

		for _, wf := range additionalWorkflows {
			if strings.HasPrefix(wf.Path, prefix) {
				additionalWorkflowsForEnvironment = append(additionalWorkflowsForEnvironment, wf)
			}
		}

		return additionalWorkflowsForEnvironment
	}

	return additionalWorkflows
}
