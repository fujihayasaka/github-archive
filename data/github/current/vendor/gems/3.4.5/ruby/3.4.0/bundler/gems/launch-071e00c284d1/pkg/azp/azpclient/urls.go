package azpclient

import (
	"fmt"
	"net/url"

	"github.com/golang/protobuf/ptypes/wrappers"

	"github.com/github/launch/types"
)

type urlBuilder struct {
	acServiceBaseURL                   string
	runnersServiceBaseURL              string
	runnersServiceIsDirectScaleUnitURL bool
	repoBaseURL                        string
	repoExternalBaseURL                string

	tenantName  string
	tenantID    string
	projectName string
	pipelineID  int64
}

func (u *urlBuilder) getRunnersAccessPolicyURL(poolID int64) string {
	return fmt.Sprintf("%s/%s/_apis/distributedtask/pools/%d/accesspolicy?api-version=6.0-preview", u.repoBaseURL, u.tenantName, poolID)
}

func (u *urlBuilder) getListRunnersV2URL(poolID, page, perPage int64, includeAssignedRequest bool, runnerName string, excludeElasticRunners bool) string {
	uri := fmt.Sprintf("%s/%s/_apis/distributedtask/pools/%d/agents?api-version=6.0-preview",
		u.repoBaseURL, u.tenantName, poolID)

	if page != 0 && perPage != 0 {
		uri = fmt.Sprintf("%s&page=%d&perPage=%d", uri, page, perPage)
	}
	if includeAssignedRequest {
		uri = fmt.Sprintf("%s&includeAssignedRequest=true", uri)
	}
	if runnerName != "" {
		uri = fmt.Sprintf("%s&agentName=%s", uri, url.QueryEscape(runnerName))
	}
	if excludeElasticRunners {
		uri = fmt.Sprintf("%s&excludeElasticRunners=true", uri)
	}

	return uri
}

func (u *urlBuilder) getUpdateRunnersURL(poolID int64) string {
	return fmt.Sprintf("%s/%s/_apis/distributedtask/pools/%d/agents?api-version=6.0-preview", u.repoBaseURL, u.tenantName, poolID)
}

func (u *urlBuilder) getRunnerURL(poolID int64, runnerID int64) string {
	return fmt.Sprintf("%s/%s/_apis/distributedtask/pools/%d/agents/%d?api-version=6.0-preview&includeAssignedRequest=true&includeCapabilities=true", u.repoBaseURL, u.tenantName, poolID, runnerID)
}

func (u *urlBuilder) getDeleteRunnerURL(poolID, runnerID int64) string {
	return fmt.Sprintf("%s/%s/_apis/distributedtask/pools/%d/agents/%d?api-version=5.1", u.repoBaseURL, u.tenantName, poolID, runnerID)
}

func (u *urlBuilder) getJITRunnerConfigURL() string {
	return fmt.Sprintf("%s/%s/_apis/distributedtask/agents/jitconfig?api-version=6.0-preview", u.repoBaseURL, u.tenantName)
}

func (u *urlBuilder) getRunnerRegistrationURL() string {
	return fmt.Sprintf("%s/%s/_apis/distributedtask/pools/1/admintoken?api-version=5.0-preview", u.repoBaseURL, u.tenantName)
}

func (u *urlBuilder) getExternalOrgServiceBaseURL() string {
	if u.repoExternalBaseURL == "" {
		return fmt.Sprintf("%s/%s", u.repoBaseURL, u.tenantName)
	}
	// In GHES we need a different URL for calls that originate outside the actual instance itself
	return fmt.Sprintf("%s/%s", u.repoExternalBaseURL, u.tenantName)
}

func (u *urlBuilder) getListDownloadsURL() string {
	return fmt.Sprintf("%s/%s/_apis/distributedtask/packages/agent?$top=1&includeToken=true", u.repoBaseURL, u.tenantName)
}

func (u *urlBuilder) getQueueBuildURL() string {
	return fmt.Sprintf("%s/%s/%s/_apis/pipelines/%d/runs?api-version=5.2-preview", u.repoBaseURL, u.tenantName, u.projectName, u.pipelineID)
}

func (u *urlBuilder) getBuildURL(workflowRunID string) string {
	return fmt.Sprintf("%s/%s/%s/_apis/pipelines/%d/runs/%s?api-version=5.2-preview", u.repoBaseURL, u.tenantName, u.projectName, u.pipelineID, workflowRunID)
}

func (u *urlBuilder) getRunInfoURL(workflowBuildID types.WorkflowExecutionID) string {
	return fmt.Sprintf("%s/%s/%s/_apis/pipelines/runinfo/%s", u.repoBaseURL, u.tenantName, u.projectName, workflowBuildID)
}

func (u *urlBuilder) getReportAdminEventsURL() string {
	return fmt.Sprintf("%s/%s/_apis/pipelines/adminevents?api-version=6.0-preview", u.repoBaseURL, u.tenantName)
}

func (u *urlBuilder) getDeleteBuildLogsURL(workflowRunID string) string {
	return fmt.Sprintf("%s/%s/%s/_apis/pipelines/%d/runs/%s/logs?api-version=5.1-preview", u.repoBaseURL, u.tenantName, u.projectName, u.pipelineID, workflowRunID)
}

func (u *urlBuilder) getDeleteBuildLogsURLByPlanID(planID string) string {
	return fmt.Sprintf("%s/%s/_apis/pipelines/plans/%s/logs?api-version=6.0-preview", u.repoBaseURL, u.tenantName, planID)
}

func (u *urlBuilder) getRunnerGroupURLbyGroupID(groupID int64) string {
	return fmt.Sprintf("%s/%s/_apis/runtime/runnergroups/%d?api-version=6.0-preview&includeVisibility=true&excludeHostedRunnerGroups=true", u.repoBaseURL, u.tenantName, groupID)
}

func (u *urlBuilder) getRunnerGroupsURL() string {
	return fmt.Sprintf("%s/%s/_apis/runtime/runnergroups?api-version=6.0-preview", u.repoBaseURL, u.tenantName)
}

func (u *urlBuilder) getRunnerGroupURLbyGroupIDFor(groupID int64, ownerID, parentID, parentTenantName string, includeRunners bool, isEnterpriseOwner bool, excludeHostedRunnerGroups bool, excludeElasticRunners bool, includeRunnerScaleSets bool) string {
	uri := fmt.Sprintf("%s/%s/_apis/runtime/runnergroups/%d?api-version=6.0-preview&includeRunners=%t&currentTenant=%s&isCurrentTenantEnterprise=%t&includeVisibility=true&excludeHostedRunnerGroups=%t&excludeElasticRunners=%t&includeRunnerScaleSets=%t", u.repoBaseURL, u.tenantName, groupID, includeRunners, url.QueryEscape(ownerID), isEnterpriseOwner, excludeHostedRunnerGroups, excludeElasticRunners, includeRunnerScaleSets)

	if ownerID != parentID {
		return fmt.Sprintf("%s&parentTenant=%s&parentTenantName=%s", uri, url.QueryEscape(parentID), parentTenantName)
	}

	return uri
}

func (u *urlBuilder) getListRunnerGroupsURL(includeRunners bool, ownerID, parentID, parentTenantName string, isEnterpriseOwner bool, excludeHostedRunnerGroups bool, excludeElasticRunners bool, includeRunnerScaleSets bool) string {
	uri := fmt.Sprintf("%s/%s/_apis/runtime/runnergroups/?api-version=6.0-preview&includeRunners=%t&currentTenant=%s&isCurrentTenantEnterprise=%t&excludeHostedRunnerGroups=%t&includeVisibility=true&excludeElasticRunners=%t&includeRunnerScaleSets=%t", u.repoBaseURL, u.tenantName, includeRunners, url.QueryEscape(ownerID), isEnterpriseOwner, excludeHostedRunnerGroups, excludeElasticRunners, includeRunnerScaleSets)

	if ownerID != parentID {
		return fmt.Sprintf("%s&parentTenant=%s&parentTenantName=%s", uri, url.QueryEscape(parentID), parentTenantName)
	}

	return uri
}

func (u *urlBuilder) getRunnerGroupVisibilityURL(groupID int64) string {
	return fmt.Sprintf("%s/%s/_apis/runtime/runnergroups/%d/visibility?api-version=6.0-preview", u.repoBaseURL, u.tenantName, groupID)
}

// Used in DELETE calls to delete artifacts
func (u *urlBuilder) getDeleteArtifactURL(workflowRunID string, artifactName string) string {
	artifactName = url.PathEscape(artifactName)
	return fmt.Sprintf("%s/%s/%s/_apis/pipelines/%d/runs/%s/artifacts?artifactName=%s&api-version=5.2-preview", u.repoBaseURL, u.tenantName, u.projectName, u.pipelineID, workflowRunID, artifactName)
}

// Used in DELETE calls to delete artifacts for a build by planID
func (u *urlBuilder) getDeleteArtifactURLByPlanID(planID string, artifactName string) string {
	artifactName = url.PathEscape(artifactName)
	return fmt.Sprintf("%s/%s/_apis/pipelines/plans/%s/artifacts?artifactName=%s&api-version=6.0-preview", u.repoBaseURL, u.tenantName, planID, artifactName)
}

func (u *urlBuilder) getLabelsURL() string {
	return fmt.Sprintf("%s/%s/_apis/distributedtask/labels?api-version=6.0-preview", u.repoBaseURL, u.tenantName)
}

func (u *urlBuilder) getDeleteLabelURL(labelID int64) string {
	return fmt.Sprintf("%s/%s/_apis/distributedtask/labels/%d?api-version=6.0-preview", u.repoBaseURL, u.tenantName, labelID)
}

func (u *urlBuilder) getUpdateGateURL(gateID string) string {
	return fmt.Sprintf("%s/%s/_apis/actions/gates/%s?api-version=6.0-preview", u.repoBaseURL, u.tenantName, gateID)
}

func (u *urlBuilder) getStepsFromChangeIDURL(jobID, planID string, changeID int64) string {
	return fmt.Sprintf("%s/%s/_apis/pipelines/plans/%s/jobs/%s/steps?api-version=6.0-preview&changeId=%d", u.repoBaseURL, u.tenantName, planID, jobID, changeID)
}

func (u *urlBuilder) getJobStepsFromChangeIDURL(planID string, changeID int64, onlyInProgressJobs bool) string {
	return fmt.Sprintf("%s/%s/_apis/pipelines/plans/%s/jobs/?api-version=6.0-preview&changeId=%d&onlyInProgressJobs=%t", u.repoBaseURL, u.tenantName, planID, changeID, onlyInProgressJobs)
}

func (u *urlBuilder) getListRunnerPoolsURL(entityID, ownerID, parentID types.GlobalID, parentTenantName string, parentTenantID string, isPrivateEntity bool, isPublicIPEnabled *wrappers.BoolValue) string {
	uri := fmt.Sprintf("%s/%s/_apis/runner/pools?api-version=1.0&currentTenant=%s",
		u.runnersServiceBaseURL, u.tenantName, url.QueryEscape(ownerID.String()))

	if !ownerID.IsEquivalent(parentID) {
		uri = fmt.Sprintf("%s&parentTenant=%s&parentTenantName=%s&parentTenantID=%s",
			uri, url.QueryEscape(parentID.String()), parentTenantName, parentTenantID)
	}

	if !entityID.IsEquivalent(ownerID) {
		uri = fmt.Sprintf("%s&filterTenant=%s&isFilterTenantPrivate=%t",
			uri, url.QueryEscape(entityID.String()), isPrivateEntity)
	}

	if isPublicIPEnabled != nil {
		uri = fmt.Sprintf("%s&isPublicIPEnabled=%t", uri, isPublicIPEnabled.Value)
	}

	return uri
}

func (u *urlBuilder) getRunnerPoolURL(poolID int64) string {
	return fmt.Sprintf("%s/%s/_apis/runner/pools/%d?api-version=1.0", u.runnersServiceBaseURL, u.tenantName, poolID)
}

func (u *urlBuilder) getRunnerPoolsURL() string {
	return fmt.Sprintf("%s/%s/_apis/runner/pools?api-version=1.0", u.runnersServiceBaseURL, u.tenantName)
}

func (u *urlBuilder) getRunnerCustomImagesURL() string {
	return fmt.Sprintf("%s/%s/_apis/runner/images/custom?api-version=6.0-preview", u.runnersServiceBaseURL, u.tenantName)
}

func (u *urlBuilder) getRunnerCustomImageURL(definitionID int64) string {
	return fmt.Sprintf("%s/%s/_apis/runner/images/custom/%d?api-version=6.0-preview", u.runnersServiceBaseURL, u.tenantName, definitionID)
}

func (u *urlBuilder) getRunnerCustomImageVersionsURL(definitionID int64, pattern *string) string {
	uri := fmt.Sprintf("%s/%s/_apis/runner/images/custom/%d/versions?api-version=6.0-preview", u.runnersServiceBaseURL, u.tenantName, definitionID)
	if pattern != nil {
		uri = fmt.Sprintf("%s&pattern=%s", uri, url.QueryEscape(*pattern))
	}

	return uri
}

func (u *urlBuilder) getRunnerCustomImageVersionURL(definitionID int64, imageVersion string) string {
	return fmt.Sprintf("%v/%v/_apis/runner/images/custom/%v/versions/%v?api-version=6.0-preview", u.runnersServiceBaseURL, u.tenantName, definitionID, imageVersion)
}

func (u *urlBuilder) getRunnerPoolAgentsURL(poolID int64) string {
	return fmt.Sprintf("%s/%s/_apis/runner/pools/%d/agents?api-version=6.0-preview", u.runnersServiceBaseURL, u.tenantName, poolID)
}

func (u *urlBuilder) getRunnerMachineSpecsURL() string {
	return fmt.Sprintf("%s/%s/_apis/runner/machinespecs?api-version=6.0-preview", u.runnersServiceBaseURL, u.tenantName)
}

func (u *urlBuilder) getRunnerCuratedImagesURL() string {
	return fmt.Sprintf("%s/%s/_apis/runner/images/curated?api-version=6.0-preview", u.runnersServiceBaseURL, u.tenantName)
}

func (u *urlBuilder) getRunnerMarketplaceImagesURL() string {
	return fmt.Sprintf("%s/%s/_apis/runner/images/marketplace?api-version=6.0-preview", u.runnersServiceBaseURL, u.tenantName)
}

func (u *urlBuilder) getRunnerReportAdminEventsURL() string {
	return fmt.Sprintf("%s/%s/_apis/runner/adminevents?api-version=1.0", u.runnersServiceBaseURL, u.tenantName)
}

func (u *urlBuilder) getRunnerScaleUnitInfoURL() string {
	return fmt.Sprintf("%s/servicehosts/%s/_apis/connectiondata", u.runnersServiceBaseURL, u.tenantID)
}

func (u *urlBuilder) getRunnerLabelsURL() string {
	return fmt.Sprintf("%s/%s/_apis/runner/labels?api-version=6.0-preview", u.runnersServiceBaseURL, u.tenantName)
}

func (u *urlBuilder) getListCacheURL(key, scope, sort, direction string, page, perPage int64) string {
	return fmt.Sprintf("%v/%v/_apis/artifactcache/caches?api-version=6.0-preview.1&key=%s&scope=%v&sort=%v&direction=%v&page=%v&perPage=%v", u.acServiceBaseURL, u.tenantName, url.QueryEscape(key), url.QueryEscape(scope), sort, direction, page, perPage)
}

func (u *urlBuilder) getDeleteCachesByKeyURL(key, scope string) string {
	return fmt.Sprintf("%v/%v/_apis/artifactcache/caches?api-version=6.0-preview.1&key=%v&scope=%v", u.acServiceBaseURL, u.tenantName, url.QueryEscape(key), url.QueryEscape(scope))
}

func (u *urlBuilder) getDeleteCacheByIDURL(cacheID int64) string {
	return fmt.Sprintf("%v/%v/_apis/artifactcache/caches/%v?api-version=6.0-preview.1", u.acServiceBaseURL, u.tenantName, cacheID)
}

func (u *urlBuilder) getRunnerScaleSetURL(scaleSetID int64) string {
	return fmt.Sprintf("%s/%s/_apis/runtime/runnerscalesets/%d?api-version=6.0-preview", u.repoBaseURL, u.tenantName, scaleSetID)
}

func (u *urlBuilder) getRunnerScaleSetsURL(excludeElasticRunners bool) string {
	return fmt.Sprintf("%s/%s/_apis/runtime/runnerscalesets?api-version=6.0-preview&excludeElasticRunners=%t", u.repoBaseURL, u.tenantName, excludeElasticRunners)
}

func (u *urlBuilder) getPipelineServiceURL() string {
	return fmt.Sprintf("%s/%s/", u.repoBaseURL, u.tenantName)
}

func (u *urlBuilder) getCacheServiceURL() string {
	return fmt.Sprintf("%s/%s/", u.acServiceBaseURL, u.tenantName)
}

func (u *urlBuilder) getRunnerBetaFeaturesURL() string {
	return fmt.Sprintf("%s/%s/_apis/runner/betafeatures?api-version=6.0-preview", u.runnersServiceBaseURL, u.tenantName)
}

func (u *urlBuilder) getRunnerBetaFeatureURL(featureName string) string {
	return fmt.Sprintf("%s/%s/_apis/runner/betafeatures/%s?api-version=6.0-preview", u.runnersServiceBaseURL, u.tenantName, featureName)
}
