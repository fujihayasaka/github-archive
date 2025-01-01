# API Reference

# Table of Contents


<details><summary>Services (1)</summary>

  - [Insights](#insights)


</details>


<details><summary>Messages (3)</summary>

  - [GetAlertsForInsightsBackfillRequest](#getalertsforinsightsbackfillrequest)
  - [GetAlertsForInsightsBackfillRequestResponse](#getalertsforinsightsbackfillrequestresponse)
  - [InsightsAlert](#insightsalert)


</details>




<details><summary>Services (1)</summary>

  - [ManagedAnalyses](#managedanalyses)


</details>


<details><summary>Messages (14)</summary>

  - [AdjustRequest](#adjustrequest)
  - [AdjustResponse](#adjustresponse)
  - [CodeQLConfig](#codeqlconfig)
  - [DisableRequest](#disablerequest)
  - [DisableResponse](#disableresponse)
  - [EnableRequest](#enablerequest)
  - [EnableResponse](#enableresponse)
  - [GetManagedAnalysisInfoRequest](#getmanagedanalysisinforequest)
  - [GetManagedAnalysisInfoResponse](#getmanagedanalysisinforesponse)
  - [LanguageList](#languagelist)
  - [UpdateLanguagesRequest](#updatelanguagesrequest)
  - [UpdateLanguagesResponse](#updatelanguagesresponse)
  - [UpdateRequest](#updaterequest)
  - [UpdateResponse](#updateresponse)


</details>


<details><summary>Enums (5)</summary>

  - [NewConfigTrigger](#newconfigtrigger)
  - [OnboardingStatusV2](#onboardingstatusv2)
  - [QuerySuite](#querysuite)
  - [ThreatModel](#threatmodel)
  - [UpdateRequest.RunnerType](#updaterequestrunnertype)


</details>



<details><summary>Services (1)</summary>

  - [Results](#results)


</details>


<details><summary>Messages (142)</summary>

  - [AlertConfigurationStatus](#alertconfigurationstatus)
  - [AlertConfigurationStatusesRequest](#alertconfigurationstatusesrequest)
  - [AlertConfigurationStatusesResponse](#alertconfigurationstatusesresponse)
  - [AlertInPullRequest](#alertinpullrequest)
  - [AlertInstance](#alertinstance)
  - [AlertInstancesRequest](#alertinstancesrequest)
  - [AlertInstancesResponse](#alertinstancesresponse)
  - [AlertLink](#alertlink)
  - [AlertLinkPayload](#alertlinkpayload)
  - [AlertRequest](#alertrequest)
  - [AlertResponse](#alertresponse)
  - [AlertTitlesRequest](#alerttitlesrequest)
  - [AlertTitlesResponse](#alerttitlesresponse)
  - [AlertsByRepoRequest](#alertsbyreporequest)
  - [AlertsByRepoResponse](#alertsbyreporesponse)
  - [AlertsRequest](#alertsrequest)
  - [AlertsResponse](#alertsresponse)
  - [AnalysesRequest](#analysesrequest)
  - [AnalysesResponse](#analysesresponse)
  - [Analysis](#analysis)
  - [AnalysisKey](#analysiskey)
  - [AnalysisMessage](#analysismessage)
  - [AnalysisRequest](#analysisrequest)
  - [AnalysisResponse](#analysisresponse)
  - [AnalysisSarifRequest](#analysissarifrequest)
  - [AnalysisSarifResponse](#analysissarifresponse)
  - [AnnotationResult](#annotationresult)
  - [AnnotationsRequest](#annotationsrequest)
  - [AnnotationsResponse](#annotationsresponse)
  - [CategoryStatus](#categorystatus)
  - [CategoryStatus.QuerySuite](#categorystatusquerysuite)
  - [Change](#change)
  - [CodePath](#codepath)
  - [CodePathStep](#codepathstep)
  - [CodePathsRequest](#codepathsrequest)
  - [CodePathsResponse](#codepathsresponse)
  - [ConfigurationGroup](#configurationgroup)
  - [CountsByCampaignsRequest](#countsbycampaignsrequest)
  - [CountsByCampaignsResponse](#countsbycampaignsresponse)
  - [CountsByCampaignsResponse.CampaignCounts](#countsbycampaignsresponsecampaigncounts)
  - [CountsByRepoRequest](#countsbyreporequest)
  - [CountsByRepoResponse](#countsbyreporesponse)
  - [CountsByRepoResponse.RepositoryCounts](#countsbyreporesponserepositorycounts)
  - [CountsByToolRequest](#countsbytoolrequest)
  - [CountsByToolResponse](#countsbytoolresponse)
  - [CountsRequest](#countsrequest)
  - [CountsResponse](#countsresponse)
  - [CreateAlertLinksRequest](#createalertlinksrequest)
  - [CreateAlertLinksResponse](#createalertlinksresponse)
  - [CreateDeliveryRequest](#createdeliveryrequest)
  - [CreateDeliveryRequest.InvalidSarif](#createdeliveryrequestinvalidsarif)
  - [CreateDeliveryRequest.InvalidZip](#createdeliveryrequestinvalidzip)
  - [CreateDeliveryRequest.SarifTooBig](#createdeliveryrequestsariftoobig)
  - [CreateDeliveryRequest.ZipTooBig](#createdeliveryrequestziptoobig)
  - [CreateDeliveryResponse](#createdeliveryresponse)
  - [CreateSecurityCampaignAlertsRequest](#createsecuritycampaignalertsrequest)
  - [CreateSecurityCampaignAlertsResponse](#createsecuritycampaignalertsresponse)
  - [Cursor](#cursor)
  - [DeleteAlertLinksRequest](#deletealertlinksrequest)
  - [DeleteAlertLinksResponse](#deletealertlinksresponse)
  - [DeleteAnalysisRequest](#deleteanalysisrequest)
  - [DeleteAnalysisResponse](#deleteanalysisresponse)
  - [DeleteSecurityCampaignAlertsRequest](#deletesecuritycampaignalertsrequest)
  - [DeleteSecurityCampaignAlertsResponse](#deletesecuritycampaignalertsresponse)
  - [DeliveryRequest](#deliveryrequest)
  - [DeliveryResponse](#deliveryresponse)
  - [DiffedAlert](#diffedalert)
  - [EnvironmentData](#environmentdata)
  - [EvalRefUpdateRulesRequest](#evalrefupdaterulesrequest)
  - [EvalRefUpdateRulesRequest.RuleConfig](#evalrefupdaterulesrequestruleconfig)
  - [EvalRefUpdateRulesRequest.ToolConfig](#evalrefupdaterulesrequesttoolconfig)
  - [EvalRefUpdateRulesResponse](#evalrefupdaterulesresponse)
  - [EvalRefUpdateRulesResponse.EvalResult](#evalrefupdaterulesresponseevalresult)
  - [ExtractedCategoryFiles](#extractedcategoryfiles)
  - [ExtractedCategoryFiles.LanguagesEntry](#extractedcategoryfileslanguagesentry)
  - [ExtractedFile](#extractedfile)
  - [ExtractedLanguageFiles](#extractedlanguagefiles)
  - [FileChange](#filechange)
  - [FilesExtractedRequest](#filesextractedrequest)
  - [FilesExtractedResponse](#filesextractedresponse)
  - [FilesExtractedResponse.CategoriesEntry](#filesextractedresponsecategoriesentry)
  - [FilesExtractedSummaryRequest](#filesextractedsummaryrequest)
  - [FilesExtractedSummaryResponse](#filesextractedsummaryresponse)
  - [FilesExtractedSummaryResponse.LanguagesExtractedEntry](#filesextractedsummaryresponselanguagesextractedentry)
  - [GetCodeScanningEnabledRequest](#getcodescanningenabledrequest)
  - [GetCodeScanningEnabledResponse](#getcodescanningenabledresponse)
  - [GetLinksForAlertsRequest](#getlinksforalertsrequest)
  - [GetLinksForAlertsResponse](#getlinksforalertsresponse)
  - [Location](#location)
  - [MissingCategorySummary](#missingcategorysummary)
  - [NewCategorySummary](#newcategorysummary)
  - [OrgRule](#orgrule)
  - [OrgRuleTag](#orgruletag)
  - [OutdatedConfiguration](#outdatedconfiguration)
  - [ProcessError](#processerror)
  - [PullRequestAlertsRequest](#pullrequestalertsrequest)
  - [PullRequestAlertsResponse](#pullrequestalertsresponse)
  - [PullRequestAlertsResponse.MissingCategoriesEntry](#pullrequestalertsresponsemissingcategoriesentry)
  - [PullRequestAlertsResponse.NewCategoriesEntry](#pullrequestalertsresponsenewcategoriesentry)
  - [PullRequestIntroducedAlertsRequest](#pullrequestintroducedalertsrequest)
  - [PullRequestIntroducedAlertsResponse](#pullrequestintroducedalertsresponse)
  - [RelatedLocation](#relatedlocation)
  - [RepoResult](#reporesult)
  - [RepositoryIDsForOrgRequest](#repositoryidsfororgrequest)
  - [RepositoryIDsResponse](#repositoryidsresponse)
  - [RepositoryIDsResponse.Repository](#repositoryidsresponserepository)
  - [Result](#result)
  - [Rule](#rule)
  - [RuleOrigin](#ruleorigin)
  - [RuleTagsForOrgRequest](#ruletagsfororgrequest)
  - [RuleTagsForOrgResponse](#ruletagsfororgresponse)
  - [RuleTagsRequest](#ruletagsrequest)
  - [RuleTagsResponse](#ruletagsresponse)
  - [RulesForOrgRequest](#rulesfororgrequest)
  - [RulesForOrgResponse](#rulesfororgresponse)
  - [RulesRequest](#rulesrequest)
  - [RulesResponse](#rulesresponse)
  - [SetAlertsStatusRequest](#setalertsstatusrequest)
  - [SetAlertsStatusResponse](#setalertsstatusresponse)
  - [SeveritiesForOrgRequest](#severitiesfororgrequest)
  - [SeveritiesForOrgResponse](#severitiesfororgresponse)
  - [SeveritiesForOrgResponse.SeverityItem](#severitiesfororgresponseseverityitem)
  - [TimelineEvent](#timelineevent)
  - [TimelineEventsRequest](#timelineeventsrequest)
  - [TimelineEventsResponse](#timelineeventsresponse)
  - [ToolAlertCount](#toolalertcount)
  - [ToolDescription](#tooldescription)
  - [ToolNamesForOrgRequest](#toolnamesfororgrequest)
  - [ToolNamesRequest](#toolnamesrequest)
  - [ToolNamesResponse](#toolnamesresponse)
  - [ToolStatus](#toolstatus)
  - [ToolStatusExtracted](#toolstatusextracted)
  - [ToolStatusRequest](#toolstatusrequest)
  - [ToolStatusResponse](#toolstatusresponse)
  - [ToolStatusRulesRequest](#toolstatusrulesrequest)
  - [ToolStatusRulesResponse](#toolstatusrulesresponse)
  - [ToolStatusRulesResponse.CategoriesEntry](#toolstatusrulesresponsecategoriesentry)
  - [ToolStatusRulesResponse.CategoryRules](#toolstatusrulesresponsecategoryrules)
  - [ToolStatusRulesResponse.CategoryRules.Rule](#toolstatusrulesresponsecategoryrulesrule)
  - [ToolStatusRulesResponse.CategoryRules.RuleOrigins](#toolstatusrulesresponsecategoryrulesruleorigins)
  - [TotalCountsForCampaignsRequest](#totalcountsforcampaignsrequest)
  - [TotalCountsForCampaignsResponse](#totalcountsforcampaignsresponse)


</details>


<details><summary>Enums (10)</summary>

  - [AlertSortOrder](#alertsortorder)
  - [AnalysesSortOrder](#analysessortorder)
  - [AnalysisMessageLevel](#analysismessagelevel)
  - [AnalysisStatus](#analysisstatus)
  - [CategoryStatus.QuerySuite.Type](#categorystatusquerysuitetype)
  - [DeliveryOrigin](#deliveryorigin)
  - [EvalRefUpdateRulesRequest.SecuritySeverityChoice](#evalrefupdaterulesrequestsecurityseveritychoice)
  - [EvalRefUpdateRulesRequest.SeverityChoice](#evalrefupdaterulesrequestseveritychoice)
  - [SearchStatus](#searchstatus)
  - [TimelineEventType](#timelineeventtype)


</details>



<details><summary>Services (1)</summary>

  - [SuggestedFixes](#suggestedfixes)


</details>


<details><summary>Messages (21)</summary>

  - [Advisory](#advisory)
  - [ApplySuggestedFixRequest](#applysuggestedfixrequest)
  - [ApplySuggestedFixResponse](#applysuggestedfixresponse)
  - [DependencyMetadata](#dependencymetadata)
  - [GenerateDependabotFixRequest](#generatedependabotfixrequest)
  - [GenerateDependabotFixResponse](#generatedependabotfixresponse)
  - [GenerateSuggestedFixRequest](#generatesuggestedfixrequest)
  - [GenerateSuggestedFixResponse](#generatesuggestedfixresponse)
  - [GenerateSyncFixRequest](#generatesyncfixrequest)
  - [GenerateSyncFixResponse](#generatesyncfixresponse)
  - [GetSuggestedFixRequest](#getsuggestedfixrequest)
  - [GetSuggestedFixResponse](#getsuggestedfixresponse)
  - [GetSuggestedFixResponse.SuggestedFixAlertsEntry](#getsuggestedfixresponsesuggestedfixalertsentry)
  - [GetSuggestedFixStatesForOrgRequest](#getsuggestedfixstatesfororgrequest)
  - [GetSuggestedFixStatesForOrgResponse](#getsuggestedfixstatesfororgresponse)
  - [GetSuggestedFixStatisticsRequest](#getsuggestedfixstatisticsrequest)
  - [GetSuggestedFixStatisticsResponse](#getsuggestedfixstatisticsresponse)
  - [RepoSuggestedFixState](#reposuggestedfixstate)
  - [SuggestedFix](#suggestedfix)
  - [SuggestedFixAlert](#suggestedfixalert)
  - [SuggestedFixFile](#suggestedfixfile)


</details>


<details><summary>Enums (4)</summary>

  - [AdvisorySeverity](#advisoryseverity)
  - [GenerateSyncFixError](#generatesyncfixerror)
  - [SuggestedFixAlertState](#suggestedfixalertstate)
  - [SuggestedFixSource](#suggestedfixsource)


</details>




<details><summary>Messages (2)</summary>

  - [AlertsFilter](#alertsfilter)
  - [RepoNumber](#reponumber)


</details>


<details><summary>Enums (11)</summary>

  - [AlertClassificationFilter](#alertclassificationfilter)
  - [AlertLinksFilter](#alertlinksfilter)
  - [AlertStateFilter](#alertstatefilter)
  - [AutofixFilter](#autofixfilter)
  - [CampaignPresenceFilter](#campaignpresencefilter)
  - [RepositoryVisibility](#repositoryvisibility)
  - [ResultResolution](#resultresolution)
  - [ResultResolutionFilter](#resultresolutionfilter)
  - [RuleSeverity](#ruleseverity)
  - [SecuritySeverity](#securityseverity)
  - [Severity](#severity)


</details>



<details><summary>Scalar Value Types (15)</summary>

  - [double](#double)
  - [float](#float)
  - [int32](#int32)
  - [int64](#int64)
  - [uint32](#uint32)
  - [uint64](#uint64)
  - [sint32](#sint32)
  - [sint64](#sint64)
  - [fixed32](#fixed32)
  - [fixed64](#fixed64)
  - [sfixed32](#sfixed32)
  - [sfixed64](#sfixed64)
  - [bool](#bool)
  - [string](#string)
  - [bytes](#bytes)


</details>



# Insights

Insights security overview

## GetAlertsForInsightsBackfill

> **rpc** GetAlertsForInsightsBackfill([GetAlertsForInsightsBackfillRequest](#getalertsforinsightsbackfillrequest))
    [GetAlertsForInsightsBackfillRequestResponse](#getalertsforinsightsbackfillrequestresponse)

GetAlertsForInsightsBackfill returns data for staging alerts in insights per https://github.com/github/security-center/issues/1823
See https://github.com/github/insights/blob/main/docs/engineering/design/cloud_ingestion/staging_contracts/code_scanning.md
 <!-- end methods -->
 <!-- end services -->

# Messages


## GetAlertsForInsightsBackfillRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| repository_id | [ uint64](#uint64) | none |
| next_cursor | [ string](#string) | none |
| updated_after | [ google.protobuf.Timestamp](#googleprotobuftimestamp) | Filter to only include alerts with a later `updated_at` timestamp. This filter forces API to page through alert records with a timestamp cursor on `updated_at` column and it is ignored when next_cursor is not nil. |
 <!-- end Fields -->
 <!-- end HasFields -->


## GetAlertsForInsightsBackfillRequestResponse



| Field | Type | Description |
| ----- | ---- | ----------- |
| alerts | [repeated InsightsAlert](#insightsalert) | none |
| next_cursor | [ string](#string) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## InsightsAlert



| Field | Type | Description |
| ----- | ---- | ----------- |
| id | [ uint64](#uint64) | Internal ID of the alert in op-store |
| repository_id | [ uint64](#uint64) | none |
| created_at | [ google.protobuf.Timestamp](#googleprotobuftimestamp) | none |
| closed_at | [ google.protobuf.Timestamp](#googleprotobuftimestamp) | The time when alert was closed - either by manually dismissing or fixing the code |
| updated_at | [ google.protobuf.Timestamp](#googleprotobuftimestamp) | none |
| closed | [ bool](#bool) | Reflects that alert is generally resolved - either because it's fixed, or because it was manually resolved |
| resolution | [ ResultResolution](#resultresolution) | none |
| rule_name | [ string](#string) | none |
| rule_sarif_identifier | [ string](#string) | none |
| tool_name | [ string](#string) | none |
| severity | [ SecuritySeverity](#securityseverity) | none |
| present_on_default_ref | [ bool](#bool) | none |
| number | [ uint32](#uint32) | Logical alert number mapped from the internal ID of the alert in op-store |
| has_autofix | [ bool](#bool) | none |
| autofix_accepted | [ bool](#bool) | none |
 <!-- end Fields -->
 <!-- end HasFields -->
 <!-- end messages -->

# Enums
 <!-- end Enums -->


# ManagedAnalyses

ManagedAnalyses coordinates the execution of CodeQL analyses for selected repos.
https://github.com/github/code-scanning/blob/main/docs/adrs/0027-managed-analyses.md

## Enable

> **rpc** Enable([EnableRequest](#enablerequest))
    [EnableResponse](#enableresponse)

Enable enabled the repo to managed analyses.
## Disable

> **rpc** Disable([DisableRequest](#disablerequest))
    [DisableResponse](#disableresponse)

Disabled disables the repo from managed analyses.
## GetManagedAnalysisInfo

> **rpc** GetManagedAnalysisInfo([GetManagedAnalysisInfoRequest](#getmanagedanalysisinforequest))
    [GetManagedAnalysisInfoResponse](#getmanagedanalysisinforesponse)

GetManagedAnalysisInfo returns the configuration of automatic CodeQL for a repository.
## Update

> **rpc** Update([UpdateRequest](#updaterequest))
    [UpdateResponse](#updateresponse)

Update *attempts to* change the current codeql configuration for a repository.
## UpdateLanguages

> **rpc** UpdateLanguages([UpdateLanguagesRequest](#updatelanguagesrequest))
    [UpdateLanguagesResponse](#updatelanguagesresponse)

UpdateLanguages *attempts to* change the languages in the current codeql configuration for a repository.
## Adjust

> **rpc** Adjust([AdjustRequest](#adjustrequest))
    [AdjustResponse](#adjustresponse)

Adjust updates a config following a validation run to only include the successful languages.
 <!-- end methods -->
 <!-- end services -->

# Messages


## AdjustRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| repository_id | [ uint64](#uint64) | none |
| languages | [repeated string](#string) | none |
| workflow_run_id | [ uint64](#uint64) | If this is non-zero, adjustments will only be applied if the latest validation run matches this id. |
| owner_id | [ uint64](#uint64) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## AdjustResponse


 <!-- end HasFields -->


## CodeQLConfig



| Field | Type | Description |
| ----- | ---- | ----------- |
| languages | [repeated string](#string) | none |
| updated_at | [ google.protobuf.Timestamp](#googleprotobuftimestamp) | none |
| query_suite | [ QuerySuite](#querysuite) | none |
| initial_languages | [repeated string](#string) | none |
| trigger | [ NewConfigTrigger](#newconfigtrigger) | none |
| threat_model | [ ThreatModel](#threatmodel) | none |
| runner_label | [ string](#string) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## DisableRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| repository_id | [ uint64](#uint64) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## DisableResponse



| Field | Type | Description |
| ----- | ---- | ----------- |
| noop | [ bool](#bool) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## EnableRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| repository_id | [ uint64](#uint64) | none |
| supported_languages | [repeated string](#string) | none |
| selected_languages | [repeated string](#string) | none |
| query_suite | [ QuerySuite](#querysuite) | none |
| threat_model | [ ThreatModel](#threatmodel) | none |
| enabled_by_actor_login | [ string](#string) | none |
| global_repository_id | [ string](#string) | Data that we need for Launch Dynamic Workflows We might find a better way to share this in the future. |
| enabled_by_actor_grid | [ string](#string) | data needed for triggering the validation run |
| default_ref | [ bytes](#bytes) | none |
| owner_id | [ uint64](#uint64) | none |
| has_kotlin | [ bool](#bool) | none |
| codeql_packs | [ string](#string) | none |
| runner_label | [ string](#string) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## EnableResponse



| Field | Type | Description |
| ----- | ---- | ----------- |
| workflow_run_id | [ uint64](#uint64) | maybe remove this later |
| noop | [ bool](#bool) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## GetManagedAnalysisInfoRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| repository_id | [ uint64](#uint64) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## GetManagedAnalysisInfoResponse



| Field | Type | Description |
| ----- | ---- | ----------- |
| error | [ string](#string) | Populates in case of validation run failure |
| workflow | [ string](#string) | This is mainly used in cassettes to test generation of the dynamic workflow |
| debuggable_workflow_run_id | [ uint64](#uint64) | This allows us to point users to the correct Actions logs in case of failure validating a codeql configuration |
| current_config | [ CodeQLConfig](#codeqlconfig) | none |
| next_scheduled_run_at | [ google.protobuf.Timestamp](#googleprotobuftimestamp) | none |
| active_repo | [ bool](#bool) | none |
| debuggable_config | [ CodeQLConfig](#codeqlconfig) | none |
| has_failed_update | [ bool](#bool) | none |
| query_suite | [ QuerySuite](#querysuite) | none |
| threat_model | [ ThreatModel](#threatmodel) | none |
| status_v2 | [ OnboardingStatusV2](#onboardingstatusv2) | none |
| runner_label | [ string](#string) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## LanguageList



| Field | Type | Description |
| ----- | ---- | ----------- |
| languages | [repeated string](#string) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## UpdateLanguagesRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| repository_id | [ uint64](#uint64) | none |
| default_ref | [ bytes](#bytes) | none |
| languages_added | [repeated string](#string) | none |
| languages_removed | [repeated string](#string) | none |
| owner_id | [ uint64](#uint64) | none |
| supported_languages | [repeated string](#string) | none |
| codeql_packs | [ string](#string) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## UpdateLanguagesResponse



| Field | Type | Description |
| ----- | ---- | ----------- |
| workflow_run_id | [ uint64](#uint64) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## UpdateRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| repository_id | [ uint64](#uint64) | none |
| languages | [repeated string](#string) | none |
| global_actor_id | [ string](#string) | none |
| actor_login | [ string](#string) | none |
| default_ref | [ bytes](#bytes) | none |
| query_suite | [ QuerySuite](#querysuite) | none |
| owner_id | [ uint64](#uint64) | none |
| threat_model | [ ThreatModel](#threatmodel) | none |
| selected_languages | [ LanguageList](#languagelist) | none |
| supported_languages | [repeated string](#string) | none |
| codeql_packs | [ string](#string) | none |
| runner_label | [ string](#string) | none |
| runner_type | [ UpdateRequest.RunnerType](#updaterequestrunnertype) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## UpdateResponse



| Field | Type | Description |
| ----- | ---- | ----------- |
| workflow_run_id | [ uint64](#uint64) | none |
| noop | [ bool](#bool) | none |
 <!-- end Fields -->
 <!-- end HasFields -->
 <!-- end messages -->

# Enums


## NewConfigTrigger


| Name | Number | Description |
| ---- | ------ | ----------- |
| MANUAL | 0 | none |
| LANGUAGES_CHANGE | 1 | none |
| TEMPLATE_UPGRADE | 2 | none |




## OnboardingStatusV2


| Name | Number | Description |
| ---- | ------ | ----------- |
| DISABLED | 0 | none |
| WAITING | 1 | none |
| ONBOARDING | 2 | none |
| STABLE | 3 | none |
| UPDATING | 4 | none |




## QuerySuite


| Name | Number | Description |
| ---- | ------ | ----------- |
| QUERY_SUITE_UNSPECIFIED | 0 | QUERY_SUITE_UNSPECIFIED should be used when the query suite is not specified (e.g., in a REST PATCH request) |
| QUERY_SUITE_DEFAULT | 1 | none |
| QUERY_SUITE_SECURITY_EXTENDED | 2 | none |




## ThreatModel


| Name | Number | Description |
| ---- | ------ | ----------- |
| THREAT_MODEL_UNSPECIFIED | 0 | THREAT_MODEL_UNSPECIFIED should be used when the threat model is not specified (e.g., in a REST PATCH request) |
| THREAT_MODEL_REMOTE | 1 | none |
| THREAT_MODEL_REMOTE_LOCAL | 2 | none |




## UpdateRequest.RunnerType


| Name | Number | Description |
| ---- | ------ | ----------- |
| RUNNER_TYPE_UNCHANGED | 0 | none |
| RUNNER_TYPE_LABELED | 1 | none |
| RUNNER_TYPE_STANDARD | 2 | none |


 <!-- end Enums -->


# Results

Results primarily provides a read-only view over Code scanning data and is implemented by turboscansvc.
There are a few write operations (updating an alert resolution, for example), however the majority of the operations
exist to allow the GitHub monolith to query and display Code scanning data.
To find the part of the codebase responsible for processing uploaded analyses, see hydrosvc / processor.go.

## GetAnalysis

> **rpc** GetAnalysis([AnalysisRequest](#analysisrequest))
    [AnalysisResponse](#analysisresponse)

GetAnalysis returns the data associated with a SARIF run, the tool and any processing errors that occurred.
This endpoint is primarily used by the API.
## GetAnalysisSarif

> **rpc** GetAnalysisSarif([AnalysisSarifRequest](#analysissarifrequest))
    [AnalysisSarifResponse](#analysissarifresponse)

GetAnalysisSarif reconstructs a SARIF document from the data we have in the database related to a SARIF run.
We do not return the original SARIF document, so any data that TurboScan does not use is likely to be omitted by the
document that is returned.
This endpoint is primarily used by the API.
## GetAnalyses

> **rpc** GetAnalyses([AnalysesRequest](#analysesrequest))
    [AnalysesResponse](#analysesresponse)

GetAnalyses pages through the analyses associated with a repository with some basic filtering and sorting options.
## GetAlerts

> **rpc** GetAlerts([AlertsRequest](#alertsrequest))
    [AlertsResponse](#alertsresponse)

GetAlerts pages through the logical alerts associated with a repository with filtering and sorting options.
It attempts to search the data using Elastic Search, falling back to MySQL if Elastic Search is not available.
The alert data is augmented with information like which rule produced the alert and its fixed state.
## GetAlertTitles

> **rpc** GetAlertTitles([AlertTitlesRequest](#alerttitlesrequest))
    [AlertTitlesResponse](#alerttitlesresponse)

GetAlertTitles returns a mapping between alert numbers and the short description of their rules.
It is primarily used to provide rich links to Code Scanning alerts.
## GetCounts

> **rpc** GetCounts([CountsRequest](#countsrequest))
    [CountsResponse](#countsresponse)

GetCounts returns a count of the open logical alerts associated with a repository.
It is a heavily used endpoint that is cached by the monolith.
## GetCountsByTool

> **rpc** GetCountsByTool([CountsByToolRequest](#countsbytoolrequest))
    [CountsByToolResponse](#countsbytoolresponse)

GetCountsByTool returns a count of the open logical alerts associated with a repository, broken down by the tool
that reported them.
## GetAlert

> **rpc** GetAlert([AlertRequest](#alertrequest))
    [AlertResponse](#alertresponse)

GetAlert returns the data for a single logical alert.
The alert data is augmented with information like which rule produced the alert, where it is in the codebase
and its fixed state.
## GetCodePaths

> **rpc** GetCodePaths([CodePathsRequest](#codepathsrequest))
    [CodePathsResponse](#codepathsresponse)

GetCodePaths returns where an alert is in the codebase, plus execution path details that illustrate a
possible problem in the code.
## GetRuleTags

> **rpc** GetRuleTags([RuleTagsRequest](#ruletagsrequest))
    [RuleTagsResponse](#ruletagsresponse)

GetRuleTags returns the complete set of tags that a tool has provided. This is used to power a dropdown that allows
the user to filter results based on tag. An example of a tag might be a CVE identifier, for example.
Unlike GetRules, GetRulesTags does not attempt to filter out tags for rules that do not have any alerts associated
with them.
## GetRules

> **rpc** GetRules([RulesRequest](#rulesrequest))
    [RulesResponse](#rulesresponse)

GetRules returns a list of rules for alerts associated with this repository. It excludes rules belonging to alerts
that are associated with deleted analyses.
## GetTimelineEvents

> **rpc** GetTimelineEvents([TimelineEventsRequest](#timelineeventsrequest))
    [TimelineEventsResponse](#timelineeventsresponse)

GetTimelineEvents returns the lifecycle events associated with an alert. It is used to populate the alert history.
## PullRequestAlerts

> **rpc** PullRequestAlerts([PullRequestAlertsRequest](#pullrequestalertsrequest))
    [PullRequestAlertsResponse](#pullrequestalertsresponse)

PullRequestAlerts returns the new alerts introduced in a PR, and the information needed for the "Code Scanning results" check run.
## PullRequestIntroducedAlerts

> **rpc** PullRequestIntroducedAlerts([PullRequestIntroducedAlertsRequest](#pullrequestintroducedalertsrequest))
    [PullRequestIntroducedAlertsResponse](#pullrequestintroducedalertsresponse)

PullRequestIntroducedAlerts returns all the alerts introduced in a PR including the alerts introduced and fixed in the PR.
## ToolNames

> **rpc** ToolNames([ToolNamesRequest](#toolnamesrequest))
    [ToolNamesResponse](#toolnamesresponse)

ToolNames returns names of the code scanning tools that have been run against this repository.
## Annotations

> **rpc** Annotations([AnnotationsRequest](#annotationsrequest))
    [AnnotationsResponse](#annotationsresponse)

Annotations is called when rendering the alerts on the files changed tab on pull requests. You ask it for a set of
alert numbers and it returns much the same information about the alerts as Diff does, but does not have to perform
an expensive diffing operation in order to work out which alerts to show.
## SetAlertsStatus

> **rpc** SetAlertsStatus([SetAlertsStatusRequest](#setalertsstatusrequest))
    [SetAlertsStatusResponse](#setalertsstatusresponse)

SetAlertsStatus allows the monolith to set a resolution for an alert. This can be used to resolve an alert
or reopen an alert that was resolved.
## DeleteAnalysis

> **rpc** DeleteAnalysis([DeleteAnalysisRequest](#deleteanalysisrequest))
    [DeleteAnalysisResponse](#deleteanalysisresponse)

DeleteAnalysis soft deletes an analysis record. If it was the most recent analysis then it updates the previous
analysis to be the new most recent analysis.
## GetAlertInstances

> **rpc** GetAlertInstances([AlertInstancesRequest](#alertinstancesrequest))
    [AlertInstancesResponse](#alertinstancesresponse)

GetAlertInstances returns a list of physical alerts for a specific logical alerts. It is used by both the API and
the show page, and in the Ruby code it is currently called with Turboscan.instances.
## GetAlertConfigurationStatuses

> **rpc** GetAlertConfigurationStatuses([AlertConfigurationStatusesRequest](#alertconfigurationstatusesrequest))
    [AlertConfigurationStatusesResponse](#alertconfigurationstatusesresponse)

GetAlertConfigurationStatuses returns information about the status of an alert in all configurations where that
alert has been detected. It is used for the Affected Branches section of the alert show page.
## GetDelivery

> **rpc** GetDelivery([DeliveryRequest](#deliveryrequest))
    [DeliveryResponse](#deliveryresponse)

GetDelivery returns information about a SARIF upload. A single delivery can be responsible for creating multiple
analyses.
## GetAlertsByRepo

> **rpc** GetAlertsByRepo([AlertsByRepoRequest](#alertsbyreporequest))
    [AlertsByRepoResponse](#alertsbyreporesponse)

GetAlertsByRepo is a security center endpoint which uses ElasticSearch data, augmented with information from the database
to provide alert information across a set of repository IDs.
## GetToolNamesForOrg

> **rpc** GetToolNamesForOrg([ToolNamesForOrgRequest](#toolnamesfororgrequest))
    [ToolNamesResponse](#toolnamesresponse)

GetToolNamesForOrg is a security center endpoint that uses ElasticSearch to return a list of all the tool names used across a set of repository IDs.
## GetToolStatus

> **rpc** GetToolStatus([ToolStatusRequest](#toolstatusrequest))
    [ToolStatusResponse](#toolstatusresponse)

GetToolStatus returns information about the most recent analyses uploaded to a repository. It powers the
tool status page.
## GetFilesExtracted

> **rpc** GetFilesExtracted([FilesExtractedRequest](#filesextractedrequest))
    [FilesExtractedResponse](#filesextractedresponse)

GetFilesExtracted returns information about which files were discovered by a tool during code scanning and if they
were successfully extracted or not.
## GetFilesExtractedSummary

> **rpc** GetFilesExtractedSummary([FilesExtractedSummaryRequest](#filesextractedsummaryrequest))
    [FilesExtractedSummaryResponse](#filesextractedsummaryresponse)

GetFilesExtractedSummary returns summary information about which files were discovered by a tool during code scanning.
## GetToolStatusRules

> **rpc** GetToolStatusRules([ToolStatusRulesRequest](#toolstatusrulesrequest))
    [ToolStatusRulesResponse](#toolstatusrulesresponse)

GetToolStatusRules returns the rules used by all the analyses for a ref.
## GetRulesForOrg

> **rpc** GetRulesForOrg([RulesForOrgRequest](#rulesfororgrequest))
    [RulesForOrgResponse](#rulesfororgresponse)

GetRulesForOrg is a security center endpoint that uses ElasticSearch to return a list of all the rules used across a set of repository IDs.
## GetRepositoryIDsForOrg

> **rpc** GetRepositoryIDsForOrg([RepositoryIDsForOrgRequest](#repositoryidsfororgrequest))
    [RepositoryIDsResponse](#repositoryidsresponse)

GetRepositoryIDsForOrg is a security center endpoint thatuses ElasticSearch to filter a list of repository IDs to a matching owner.
## GetSeveritiesForOrg

> **rpc** GetSeveritiesForOrg([SeveritiesForOrgRequest](#severitiesfororgrequest))
    [SeveritiesForOrgResponse](#severitiesfororgresponse)

GetSeveritiesForOrg is a security center endpoint that uses ElasticSearch to return a list of alert counts for each severity.
## GetRuleTagsForOrg

> **rpc** GetRuleTagsForOrg([RuleTagsForOrgRequest](#ruletagsfororgrequest))
    [RuleTagsForOrgResponse](#ruletagsfororgresponse)

GetRuleTagsForOrg is a security center endpoint that uses ElasticSearch to return a list of tags used across a set of repository IDs.
## GetCountsByRepo

> **rpc** GetCountsByRepo([CountsByRepoRequest](#countsbyreporequest))
    [CountsByRepoResponse](#countsbyreporesponse)

GetCountsByRepo uses ElasticSearch to return a count of the open/closed logical alerts associated with a repository,
broken down by the repository.
## GetCountsByCampaigns

> **rpc** GetCountsByCampaigns([CountsByCampaignsRequest](#countsbycampaignsrequest))
    [CountsByCampaignsResponse](#countsbycampaignsresponse)

GetCountsByCampaigns is a security campaigns endpoint that uses ElasticSearch to return a count of open alerts for the given campaigns.
## GetTotalCountsForCampaigns

> **rpc** GetTotalCountsForCampaigns([TotalCountsForCampaignsRequest](#totalcountsforcampaignsrequest))
    [TotalCountsForCampaignsResponse](#totalcountsforcampaignsresponse)

GetTotalCountsForCampaigns returns the total counts for the given filter
## CreateDelivery

> **rpc** CreateDelivery([CreateDeliveryRequest](#createdeliveryrequest))
    [CreateDeliveryResponse](#createdeliveryresponse)

CreateDelivery synchronously creates a delivery record to track SARIF uploads. If a delivery is missing when the
hydrosvc pipeline is started then it will be created. This ensures we will always have a delivery, even if
TurboScan was unavailable at time of upload.
## GetCodeScanningEnabled

> **rpc** GetCodeScanningEnabled([GetCodeScanningEnabledRequest](#getcodescanningenabledrequest))
    [GetCodeScanningEnabledResponse](#getcodescanningenabledresponse)

GetCodeScanningEnabled determines whether code scanning is considered to be enabled on a repo or not.
## EvalRefUpdateRules

> **rpc** EvalRefUpdateRules([EvalRefUpdateRulesRequest](#evalrefupdaterulesrequest))
    [EvalRefUpdateRulesResponse](#evalrefupdaterulesresponse)

EvalRefUpdateRules evaluates a list of code scanning ref update rules to determine whether the ref update should be allowed or not.
It returns a list of evaluation results in the same order that the rule configs were provided in.
See code_scanning_rule.rb in the monolith.
## GetLinksForAlerts

> **rpc** GetLinksForAlerts([GetLinksForAlertsRequest](#getlinksforalertsrequest))
    [GetLinksForAlertsResponse](#getlinksforalertsresponse)

GetLinksForAlerts fetches all linked branches and pull requests for a set of alert numbers
## CreateAlertLinks

> **rpc** CreateAlertLinks([CreateAlertLinksRequest](#createalertlinksrequest))
    [CreateAlertLinksResponse](#createalertlinksresponse)

CreateAlertLinks creates a link between an alert and a branch or pull request
## CreateSecurityCampaignAlerts

> **rpc** CreateSecurityCampaignAlerts([CreateSecurityCampaignAlertsRequest](#createsecuritycampaignalertsrequest))
    [CreateSecurityCampaignAlertsResponse](#createsecuritycampaignalertsresponse)

CreateSecurityCampaignAlerts creates security campaigns alerts
## DeleteSecurityCampaignAlerts

> **rpc** DeleteSecurityCampaignAlerts([DeleteSecurityCampaignAlertsRequest](#deletesecuritycampaignalertsrequest))
    [DeleteSecurityCampaignAlertsResponse](#deletesecuritycampaignalertsresponse)

DeleteSecurityCampaignAlerts deletes security campaigns alerts
## DeleteAlertLinks

> **rpc** DeleteAlertLinks([DeleteAlertLinksRequest](#deletealertlinksrequest))
    [DeleteAlertLinksResponse](#deletealertlinksresponse)

DeleteAlertLinks deletes alert links
 <!-- end methods -->
 <!-- end services -->

# Messages


## AlertConfigurationStatus



| Field | Type | Description |
| ----- | ---- | ----------- |
| ref_name_bytes | [ bytes](#bytes) | none |
| category | [ string](#string) | none |
| tool | [ string](#string) | none |
| created_at | [ google.protobuf.Timestamp](#googleprotobuftimestamp) | created_at(_oid) may be null if we cannot determine when the alert was first detected for this configuration |
| created_at_oid | [ string](#string) | none |
| fixed_at | [ google.protobuf.Timestamp](#googleprotobuftimestamp) | fixed_at(_oid) will be null if the alert is not fixed in this configuration |
| fixed_at_oid | [ string](#string) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## AlertConfigurationStatusesRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| repository_id | [ uint64](#uint64) | required |
| alert_number | [ uint32](#uint32) | required |
| limit | [ uint32](#uint32) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## AlertConfigurationStatusesResponse



| Field | Type | Description |
| ----- | ---- | ----------- |
| statuses | [repeated AlertConfigurationStatus](#alertconfigurationstatus) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## AlertInPullRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| alert_number | [ uint32](#uint32) | none |
| analysis_id | [ uint64](#uint64) | none |
| created_at | [ google.protobuf.Timestamp](#googleprotobuftimestamp) | none |
| updated_at | [ google.protobuf.Timestamp](#googleprotobuftimestamp) | none |
| resolution | [ ResultResolution](#resultresolution) | none |
| severity | [ SecuritySeverity](#securityseverity) | none |
| ref_name_bytes | [ bytes](#bytes) | none |
| tool | [ string](#string) | none |
| rule_sarif_identifier | [ string](#string) | none |
| has_autofix | [ bool](#bool) | none |
| autofix_accepted | [ bool](#bool) | none |
| fixed | [ bool](#bool) | none |
| fixed_at | [ google.protobuf.Timestamp](#googleprotobuftimestamp) | none |
| resolved_at | [ google.protobuf.Timestamp](#googleprotobuftimestamp) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## AlertInstance



| Field | Type | Description |
| ----- | ---- | ----------- |
| commit_oid | [ string](#string) | none |
| location | [ Location](#location) | none |
| is_fixed | [ bool](#bool) | none |
| has_file_classification | [ bool](#bool) | none |
| analysis_key | [ AnalysisKey](#analysiskey) | none |
| classification | [repeated string](#string) | none |
| message_text | [ string](#string) | none |
| created_at | [ google.protobuf.Timestamp](#googleprotobuftimestamp) | none |
| ref_name_bytes | [ bytes](#bytes) | none |
| is_outdated | [ bool](#bool) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## AlertInstancesRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| repository_id | [ uint64](#uint64) | required |
| alert_number | [ uint32](#uint32) | required |
| limit | [ uint32](#uint32) | none |
| numeric_page | [ uint32](#uint32) | none |
| skip_pagination | [ bool](#bool) | none |
| branches_only | [ bool](#bool) | none |
| no_count | [ bool](#bool) | none |
| ref_names_bytes | [repeated bytes](#bytes) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## AlertInstancesResponse



| Field | Type | Description |
| ----- | ---- | ----------- |
| instances | [repeated AlertInstance](#alertinstance) | none |
| total_count | [ uint64](#uint64) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## AlertLink



| Field | Type | Description |
| ----- | ---- | ----------- |
| repository_id | [ uint64](#uint64) | none |
| alert_number | [ uint32](#uint32) | none |
| pull_request_id | [ uint64](#uint64) | none |
| ref_name_bytes | [ bytes](#bytes) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## AlertLinkPayload



| Field | Type | Description |
| ----- | ---- | ----------- |
| alert_number | [ uint32](#uint32) | none |
| pull_request_id | [ uint64](#uint64) | none |
| ref_name_bytes | [ bytes](#bytes) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## AlertRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| repository_id | [ uint64](#uint64) | required |
| number | [ uint32](#uint32) | none |
| include_related_locations | [ bool](#bool) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## AlertResponse



| Field | Type | Description |
| ----- | ---- | ----------- |
| result | [ Result](#result) | none |
| related_locations | [repeated RelatedLocation](#relatedlocation) | none |
| rule_tags | [repeated string](#string) | none |
| has_code_paths | [ bool](#bool) | none |
| rule_help | [ string](#string) | none |
| query_uri | [ string](#string) | none |
| ref_name_bytes | [ bytes](#bytes) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## AlertTitlesRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| repository_ids | [repeated uint64](#uint64) | none |
| alert_numbers | [repeated uint32](#uint32) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## AlertTitlesResponse



| Field | Type | Description |
| ----- | ---- | ----------- |
| repository_ids | [repeated uint64](#uint64) | none |
| alert_numbers | [repeated uint32](#uint32) | none |
| titles | [repeated string](#string) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## AlertsByRepoRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| limit | [ uint32](#uint32) | none |
| numeric_page | [ uint32](#uint32) | none |
| sort_order | [ AlertSortOrder](#alertsortorder) | none |
| state | [ AlertStateFilter](#alertstatefilter) | none |
| repository_ids | [repeated uint64](#uint64) | none |
| search_query | [ string](#string) | none |
| before_cursor | [ string](#string) | none |
| after_cursor | [ string](#string) | none |
| excluded_repository_ids | [repeated uint64](#uint64) | none |
| excluded_rule_sarif_identifiers | [repeated string](#string) | none |
| excluded_tools | [repeated string](#string) | none |
| excluded_severities | [repeated Severity](#severity) | none |
| excluded_resolutions | [repeated ResultResolutionFilter](#resultresolutionfilter) | none |
| severities | [repeated Severity](#severity) | none |
| owner_ids | [repeated uint64](#uint64) | none |
| tools | [repeated string](#string) | none |
| tool_guids | [repeated string](#string) | none |
| rule_sarif_identifiers | [repeated string](#string) | none |
| rule_tags | [repeated string](#string) | none |
| excluded_rule_tags | [repeated string](#string) | none |
| repository_visibilities | [repeated RepositoryVisibility](#repositoryvisibility) | none |
| resolutions | [repeated ResultResolutionFilter](#resultresolutionfilter) | none |
| repo_numbers | [repeated RepoNumber](#reponumber) | none |
| classification | [ AlertClassificationFilter](#alertclassificationfilter) | none |
| alert_links | [ AlertLinksFilter](#alertlinksfilter) | none |
| autofix | [ AutofixFilter](#autofixfilter) | none |
| autofixes | [repeated AutofixFilter](#autofixfilter) | none |
| excluded_autofixes | [repeated AutofixFilter](#autofixfilter) | none |
| security_campaign_ids | [repeated uint64](#uint64) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## AlertsByRepoResponse



| Field | Type | Description |
| ----- | ---- | ----------- |
| results | [repeated RepoResult](#reporesult) | none |
| open_count | [ uint64](#uint64) | none |
| resolved_count | [ uint64](#uint64) | none |
| open_with_links_count | [ uint64](#uint64) | none |
| next_cursor | [ string](#string) | none |
| prev_cursor | [ string](#string) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## AlertsRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| repository_id | [ uint64](#uint64) | required |
| limit | [ uint32](#uint32) | none |
| numeric_page | [ uint32](#uint32) | none |
| resolved_only | [ bool](#bool) | none |
| sort_order | [ AlertSortOrder](#alertsortorder) | none |
| rule_tags | [repeated string](#string) | none |
| state | [ AlertStateFilter](#alertstatefilter) | none |
| classification | [ AlertClassificationFilter](#alertclassificationfilter) | none |
| search_query | [ string](#string) | none |
| excluded_rule_tags | [repeated string](#string) | none |
| severities | [repeated Severity](#severity) | none |
| tools | [repeated string](#string) | none |
| tool_guids | [repeated string](#string) | none |
| excluded_rule_ids | [repeated string](#string) | none |
| excluded_tools | [repeated string](#string) | none |
| excluded_resolutions | [repeated ResultResolutionFilter](#resultresolutionfilter) | none |
| excluded_severities | [repeated Severity](#severity) | none |
| rule_sarif_identifiers | [repeated string](#string) | none |
| resolutions | [repeated ResultResolutionFilter](#resultresolutionfilter) | none |
| ref_names_bytes | [repeated bytes](#bytes) | none |
| file_paths | [repeated string](#string) | none |
| language_file_paths | [repeated string](#string) | none |
| cursor | [ Cursor](#cursor) | none |
| numbers | [repeated uint32](#uint32) | none |
| owner_id | [ uint64](#uint64) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## AlertsResponse



| Field | Type | Description |
| ----- | ---- | ----------- |
| results | [repeated Result](#result) | none |
| open_count | [ uint64](#uint64) | none |
| resolved_count | [ uint64](#uint64) | none |
| analysis_exists | [ bool](#bool) | none |
| total_count | [ uint64](#uint64) | none |
| search_status | [ SearchStatus](#searchstatus) | none |
| next_cursor | [ string](#string) | none |
| prev_cursor | [ string](#string) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## AnalysesRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| repository_id | [ uint64](#uint64) | required |
| tool | [ string](#string) | none |
| limit | [ uint32](#uint32) | none |
| numeric_page | [ uint32](#uint32) | none |
| sarif_id | [ string](#string) | none |
| tool_guid | [ string](#string) | none |
| sort_order | [ AnalysesSortOrder](#analysessortorder) | none |
| ref_names_bytes | [repeated bytes](#bytes) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## AnalysesResponse



| Field | Type | Description |
| ----- | ---- | ----------- |
| analyses | [repeated Analysis](#analysis) | none |
| total_count | [ uint64](#uint64) | none |
| complete_analysis_exists | [ bool](#bool) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## Analysis



| Field | Type | Description |
| ----- | ---- | ----------- |
| id | [ uint64](#uint64) | none |
| analysis_key | [ string](#string) | none |
| environment | [ string](#string) | none |
| errors | [ string](#string) | none |
| created_at | [ google.protobuf.Timestamp](#googleprotobuftimestamp) | none |
| commit_oid | [ string](#string) | none |
| sarif_id | [ string](#string) | none |
| results_count | [ uint32](#uint32) | none |
| rules_count | [ uint32](#uint32) | none |
| tool_description | [ ToolDescription](#tooldescription) | none |
| most_recent | [ bool](#bool) | none |
| process_warning | [ string](#string) | none |
| category | [ string](#string) | none |
| build_started_at | [ google.protobuf.Timestamp](#googleprotobuftimestamp) | none |
| upload_started_at | [ google.protobuf.Timestamp](#googleprotobuftimestamp) | none |
| workflow_run_id | [ uint64](#uint64) | none |
| status | [ AnalysisStatus](#analysisstatus) | none |
| ref_name_bytes | [ bytes](#bytes) | none |
| delivery_origin | [ DeliveryOrigin](#deliveryorigin) | none |
| workflow_path | [ bytes](#bytes) | none |
| is_outdated | [ bool](#bool) | none |
| deletable | [ bool](#bool) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## AnalysisKey



| Field | Type | Description |
| ----- | ---- | ----------- |
| id | [ uint64](#uint64) | none |
| analysis_key | [ string](#string) | none |
| tool | [ string](#string) | none |
| environment | [ string](#string) | none |
| category | [ string](#string) | none |
| commit_oid | [ string](#string) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## AnalysisMessage
AnalysisMessage contains a serialized `ts_analysis_messages` record that describes something that happened when an
analysis was processed. These messages feed in to the overall status of a tool.


| Field | Type | Description |
| ----- | ---- | ----------- |
| title | [ string](#string) | A high level overview of this message |
| message | [ string](#string) | A markdown formatted document that contains detailed, actionable information |
| level | [ AnalysisMessageLevel](#analysismessagelevel) | The severity of this message and how it affects the tool status |
| key | [ string](#string) | The type of this message. Used when rolling up several messages of the same time and determining the priority of messages |
| locations | [repeated Location](#location) | The locations of the cause of the alert, if applicable |
| help_links | [repeated string](#string) | Links for the user that lead to further documentation |
| has_analysis | [ bool](#bool) | Does this message have a corresponding analysis or is it only related to a delivery? |
 <!-- end Fields -->
 <!-- end HasFields -->


## AnalysisRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| repository_id | [ uint64](#uint64) | required |
| analysis_id | [ uint64](#uint64) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## AnalysisResponse



| Field | Type | Description |
| ----- | ---- | ----------- |
| analysis | [ Analysis](#analysis) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## AnalysisSarifRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| repository_id | [ uint64](#uint64) | required |
| analysis_id | [ uint64](#uint64) | none |
| repo_html_url | [ string](#string) | none |
| alerts_api_url | [ string](#string) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## AnalysisSarifResponse



| Field | Type | Description |
| ----- | ---- | ----------- |
| sarif | [ string](#string) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## AnnotationResult



| Field | Type | Description |
| ----- | ---- | ----------- |
| result | [ Result](#result) | none |
| related_locations | [repeated RelatedLocation](#relatedlocation) | none |
| has_code_paths | [ bool](#bool) | none |
| is_quality | [ bool](#bool) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## AnnotationsRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| repository_id | [ uint64](#uint64) | none |
| numbers | [repeated uint32](#uint32) | none |
| head_commit_oid | [ string](#string) | none |
| merge_commit_oid | [ string](#string) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## AnnotationsResponse



| Field | Type | Description |
| ----- | ---- | ----------- |
| results | [repeated AnnotationResult](#annotationresult) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## CategoryStatus



| Field | Type | Description |
| ----- | ---- | ----------- |
| workflow_run_id | [ uint64](#uint64) | none |
| analysis_status | [ AnalysisStatus](#analysisstatus) | none |
| commit_oid | [ string](#string) | none |
| updated_at | [ google.protobuf.Timestamp](#googleprotobuftimestamp) | none |
| category | [ string](#string) | none |
| tool_version | [ string](#string) | none |
| messages | [repeated AnalysisMessage](#analysismessage) | none |
| created_at | [ google.protobuf.Timestamp](#googleprotobuftimestamp) | none |
| extensions | [repeated RuleOrigin](#ruleorigin) | none |
| analysis_id | [ uint64](#uint64) | none |
| is_outdated | [ bool](#bool) | none |
| query_suites | [repeated CategoryStatus.QuerySuite](#categorystatusquerysuite) | none |
| default_queries_disabled | [ bool](#bool) | none |
| has_most_recent | [ bool](#bool) | none |
| configuration_hash | [ bytes](#bytes) | none |
| configuration_group | [ ConfigurationGroup](#configurationgroup) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## CategoryStatus.QuerySuite



| Field | Type | Description |
| ----- | ---- | ----------- |
| type | [ CategoryStatus.QuerySuite.Type](#categorystatusquerysuitetype) | none |
| uses | [ string](#string) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## Change



| Field | Type | Description |
| ----- | ---- | ----------- |
| added | [ bool](#bool) | none |
| start_line | [ uint32](#uint32) | none |
| end_line | [ uint32](#uint32) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## CodePath



| Field | Type | Description |
| ----- | ---- | ----------- |
| steps | [repeated CodePathStep](#codepathstep) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## CodePathStep



| Field | Type | Description |
| ----- | ---- | ----------- |
| location | [ Location](#location) | none |
| message | [ string](#string) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## CodePathsRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| repository_id | [ uint64](#uint64) | none |
| number | [ uint32](#uint32) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## CodePathsResponse



| Field | Type | Description |
| ----- | ---- | ----------- |
| result | [ Result](#result) | none |
| code_paths | [repeated CodePath](#codepath) | none |
| related_locations | [repeated RelatedLocation](#relatedlocation) | none |
| ref_name_bytes | [ bytes](#bytes) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## ConfigurationGroup



| Field | Type | Description |
| ----- | ---- | ----------- |
| delivery_origin | [ DeliveryOrigin](#deliveryorigin) | none |
| workflow_path | [ bytes](#bytes) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## CountsByCampaignsRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| owner_ids | [repeated uint64](#uint64) | none |
| repository_ids | [repeated uint64](#uint64) | none |
| excluded_repository_ids | [repeated uint64](#uint64) | none |
| security_campaign_ids | [repeated uint64](#uint64) | none |
| filter | [ AlertsFilter](#alertsfilter) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## CountsByCampaignsResponse



| Field | Type | Description |
| ----- | ---- | ----------- |
| campaign_counts | [repeated CountsByCampaignsResponse.CampaignCounts](#countsbycampaignsresponsecampaigncounts) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## CountsByCampaignsResponse.CampaignCounts



| Field | Type | Description |
| ----- | ---- | ----------- |
| campaign_id | [ uint64](#uint64) | none |
| open_count | [ uint64](#uint64) | none |
| closed_count | [ uint64](#uint64) | none |
| open_with_links_count | [ uint64](#uint64) | none |
| dismissed_count | [ uint64](#uint64) | none |
| autofix_supported_count | [ uint64](#uint64) | none |
| autofix_generated_count | [ uint64](#uint64) | none |
| autofix_accepted_count | [ uint64](#uint64) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## CountsByRepoRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| owner_ids | [repeated uint64](#uint64) | none |
| repository_ids | [repeated uint64](#uint64) | none |
| excluded_repository_ids | [repeated uint64](#uint64) | none |
| filter | [ AlertsFilter](#alertsfilter) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## CountsByRepoResponse



| Field | Type | Description |
| ----- | ---- | ----------- |
| open_count | [ uint64](#uint64) | total number of open alerts |
| closed_count | [ uint64](#uint64) | total number of closed alerts |
| open_with_links_count | [ uint64](#uint64) | total number of open alerts with links |
| repository_counts | [repeated CountsByRepoResponse.RepositoryCounts](#countsbyreporesponserepositorycounts) | number of open and closed alerts by repository id |
 <!-- end Fields -->
 <!-- end HasFields -->


## CountsByRepoResponse.RepositoryCounts



| Field | Type | Description |
| ----- | ---- | ----------- |
| repository_id | [ uint64](#uint64) | none |
| open_count | [ uint64](#uint64) | none |
| closed_count | [ uint64](#uint64) | none |
| open_with_links_count | [ uint64](#uint64) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## CountsByToolRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| repository_id | [ uint64](#uint64) | required |
| ref_names_bytes | [repeated bytes](#bytes) | empty means no refs, not all refs |
 <!-- end Fields -->
 <!-- end HasFields -->


## CountsByToolResponse



| Field | Type | Description |
| ----- | ---- | ----------- |
| tool_counts | [repeated ToolAlertCount](#toolalertcount) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## CountsRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| repository_id | [ uint64](#uint64) | required |
| tool_name | [ string](#string) | none |
| ref_names_bytes | [repeated bytes](#bytes) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## CountsResponse



| Field | Type | Description |
| ----- | ---- | ----------- |
| open_count | [ uint64](#uint64) | none |
| analysis_exists | [ bool](#bool) | none |
| latest_analysis | [ google.protobuf.Timestamp](#googleprotobuftimestamp) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## CreateAlertLinksRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| repository_id | [ uint64](#uint64) | none |
| links | [repeated AlertLinkPayload](#alertlinkpayload) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## CreateAlertLinksResponse


 <!-- end HasFields -->


## CreateDeliveryRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| repository_id | [ uint64](#uint64) | required |
| repository_nwo | [ string](#string) | none |
| ref | [ bytes](#bytes) | required |
| commit_oid | [ string](#string) | required |
| sarif_id | [ string](#string) | required |
| request_id | [ string](#string) | none |
| analysis_key | [ string](#string) | none |
| environment | [ string](#string) | none |
| checkout_uri | [ string](#string) | none |
| build_started_at | [ google.protobuf.Timestamp](#googleprotobuftimestamp) | none |
| workflow_run_id | [ uint64](#uint64) | none |
| workflow_run_attempt | [ int64](#int64) | none |
| upload_started_at | [ google.protobuf.Timestamp](#googleprotobuftimestamp) | required |
| upload_finished_at | [ google.protobuf.Timestamp](#googleprotobuftimestamp) | required |
| hydro_enqueued_at | [ google.protobuf.Timestamp](#googleprotobuftimestamp) | required |
| sarif_path | [ string](#string) | required |
| source_repository_id | [ uint64](#uint64) | none |
| outdated_configuration | [ OutdatedConfiguration](#outdatedconfiguration) | none |
| rejected | [ bool](#bool) | none |
| [**oneof**](https://developers.google.com/protocol-buffers/docs/proto3#oneof) error.zip_too_big_error | [ CreateDeliveryRequest.ZipTooBig](#createdeliveryrequestziptoobig) | none |
| [**oneof**](https://developers.google.com/protocol-buffers/docs/proto3#oneof) error.sarif_too_big_error | [ CreateDeliveryRequest.SarifTooBig](#createdeliveryrequestsariftoobig) | none |
| [**oneof**](https://developers.google.com/protocol-buffers/docs/proto3#oneof) error.invalid_sarif_error | [ CreateDeliveryRequest.InvalidSarif](#createdeliveryrequestinvalidsarif) | none |
| [**oneof**](https://developers.google.com/protocol-buffers/docs/proto3#oneof) error.invalid_zip_error | [ CreateDeliveryRequest.InvalidZip](#createdeliveryrequestinvalidzip) | none |
| head_commit_oid | [ string](#string) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## CreateDeliveryRequest.InvalidSarif



| Field | Type | Description |
| ----- | ---- | ----------- |
| message | [ string](#string) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## CreateDeliveryRequest.InvalidZip



| Field | Type | Description |
| ----- | ---- | ----------- |
| empty | [ bool](#bool) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## CreateDeliveryRequest.SarifTooBig



| Field | Type | Description |
| ----- | ---- | ----------- |
| max | [ string](#string) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## CreateDeliveryRequest.ZipTooBig



| Field | Type | Description |
| ----- | ---- | ----------- |
| max | [ string](#string) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## CreateDeliveryResponse



| Field | Type | Description |
| ----- | ---- | ----------- |
| id | [ uint64](#uint64) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## CreateSecurityCampaignAlertsRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| security_campaign_id | [ uint64](#uint64) | none |
| repo_numbers | [repeated RepoNumber](#reponumber) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## CreateSecurityCampaignAlertsResponse


 <!-- end HasFields -->


## Cursor



| Field | Type | Description |
| ----- | ---- | ----------- |
| value | [ string](#string) | none |
| descending | [ bool](#bool) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## DeleteAlertLinksRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| repository_id | [ uint64](#uint64) | none |
| links | [repeated AlertLinkPayload](#alertlinkpayload) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## DeleteAlertLinksResponse


 <!-- end HasFields -->


## DeleteAnalysisRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| repository_id | [ uint64](#uint64) | none |
| analysis_id | [ uint64](#uint64) | none |
| confirm_config_delete | [ bool](#bool) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## DeleteAnalysisResponse



| Field | Type | Description |
| ----- | ---- | ----------- |
| new_most_recent_analysis_id | [ uint64](#uint64) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## DeleteSecurityCampaignAlertsRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| security_campaign_id | [ uint64](#uint64) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## DeleteSecurityCampaignAlertsResponse


 <!-- end HasFields -->


## DeliveryRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| repository_id | [ uint64](#uint64) | none |
| sarif_id | [ string](#string) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## DeliveryResponse



| Field | Type | Description |
| ----- | ---- | ----------- |
| analysis_count | [ uint64](#uint64) | none |
| errors | [repeated ProcessError](#processerror) | none |
| ref | [ bytes](#bytes) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## DiffedAlert



| Field | Type | Description |
| ----- | ---- | ----------- |
| number | [ uint32](#uint32) | none |
| rule_severity | [ RuleSeverity](#ruleseverity) | none |
| message_text | [ string](#string) | none |
| rule_short_description | [ string](#string) | none |
| location | [ Location](#location) | none |
| message_markdown | [ string](#string) | none |
| security_severity | [ SecuritySeverity](#securityseverity) | none |
| rule_sarif_identifier | [ string](#string) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## EnvironmentData



| Field | Type | Description |
| ----- | ---- | ----------- |
| key | [ string](#string) | none |
| value | [ string](#string) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## EvalRefUpdateRulesRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| repository_id | [ uint64](#uint64) | none |
| base_ref_bytes | [ bytes](#bytes) | none |
| head_commit_oid | [ string](#string) | none |
| merge_commit_oid | [ string](#string) | none |
| file_changes | [repeated FileChange](#filechange) | none |
| rule_configs | [repeated EvalRefUpdateRulesRequest.RuleConfig](#evalrefupdaterulesrequestruleconfig) | none |
| is_dependabot | [ bool](#bool) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## EvalRefUpdateRulesRequest.RuleConfig



| Field | Type | Description |
| ----- | ---- | ----------- |
| tool_configs | [repeated EvalRefUpdateRulesRequest.ToolConfig](#evalrefupdaterulesrequesttoolconfig) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## EvalRefUpdateRulesRequest.ToolConfig



| Field | Type | Description |
| ----- | ---- | ----------- |
| name | [ string](#string) | none |
| alerts_threshold | [ EvalRefUpdateRulesRequest.SeverityChoice](#evalrefupdaterulesrequestseveritychoice) | none |
| security_alerts_threshold | [ EvalRefUpdateRulesRequest.SecuritySeverityChoice](#evalrefupdaterulesrequestsecurityseveritychoice) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## EvalRefUpdateRulesResponse



| Field | Type | Description |
| ----- | ---- | ----------- |
| results | [repeated EvalRefUpdateRulesResponse.EvalResult](#evalrefupdaterulesresponseevalresult) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## EvalRefUpdateRulesResponse.EvalResult



| Field | Type | Description |
| ----- | ---- | ----------- |
| passed | [ bool](#bool) | none |
| failure_message | [ string](#string) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## ExtractedCategoryFiles
ExtractedCategoryFiles contains a mapping of languages to extracted file information


| Field | Type | Description |
| ----- | ---- | ----------- |
| languages | [map ExtractedCategoryFiles.LanguagesEntry](#extractedcategoryfileslanguagesentry) | Languages contains a map of languages that are empty if no files were extracted |
 <!-- end Fields -->
 <!-- end HasFields -->


## ExtractedCategoryFiles.LanguagesEntry



| Field | Type | Description |
| ----- | ---- | ----------- |
| key | [ string](#string) | none |
| value | [ ExtractedLanguageFiles](#extractedlanguagefiles) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## ExtractedFile
ExtractedFile contains information about a path and if it was extracted successfully.


| Field | Type | Description |
| ----- | ---- | ----------- |
| path | [ bytes](#bytes) | Path of the file that was extracted |
| success | [ bool](#bool) | Success tracks if the path was successfully extracted or not |
| message | [ bytes](#bytes) | Message contains the error message if the path was not successfully extracted |
 <!-- end Fields -->
 <!-- end HasFields -->


## ExtractedLanguageFiles
ExtractedLanguagesFiles contains the extracted file information for a language


| Field | Type | Description |
| ----- | ---- | ----------- |
| files | [repeated ExtractedFile](#extractedfile) | Files contains the list of files that were provided in the baseline |
 <!-- end Fields -->
 <!-- end HasFields -->


## FileChange



| Field | Type | Description |
| ----- | ---- | ----------- |
| file_path | [ string](#string) | none |
| changes | [repeated Change](#change) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## FilesExtractedRequest
FilesExtractedResponse requests information used for the tool status extracted files CSV download


| Field | Type | Description |
| ----- | ---- | ----------- |
| repository_id | [ uint64](#uint64) | __(Required)__ Repository ID for retrieving Tool Status information. |
| ref | [ bytes](#bytes) | __(Required)__ Ref is the branch reference, base64 encoded. |
| tool | [ string](#string) | __(Required)__ The name of the tool to provide file information for.

required |
| analysis_ids | [repeated uint64](#uint64) | __(Required)__ List of analyses to return extracted files for. |
 <!-- end Fields -->
 <!-- end HasFields -->


## FilesExtractedResponse
FilesExtractedResponse returns information used for the tool status extracted files CSV download


| Field | Type | Description |
| ----- | ---- | ----------- |
| categories | [map FilesExtractedResponse.CategoriesEntry](#filesextractedresponsecategoriesentry) | Categories contains a map of analysis categories to files that were extracted. |
 <!-- end Fields -->
 <!-- end HasFields -->


## FilesExtractedResponse.CategoriesEntry



| Field | Type | Description |
| ----- | ---- | ----------- |
| key | [ string](#string) | none |
| value | [ ExtractedCategoryFiles](#extractedcategoryfiles) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## FilesExtractedSummaryRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| repository_id | [ uint64](#uint64) | __(Required)__ Repository ID for retrieving Tool Status information. |
| ref | [ bytes](#bytes) | __(Required)__ Ref is the branch reference. |
| tool | [ string](#string) | __(Required)__ The name of the tool to provide file information for.

required |
 <!-- end Fields -->
 <!-- end HasFields -->


## FilesExtractedSummaryResponse



| Field | Type | Description |
| ----- | ---- | ----------- |
| total_extracted | [ ToolStatusExtracted](#toolstatusextracted) | Top-level information about how many files were extracted |
| languages_extracted | [map FilesExtractedSummaryResponse.LanguagesExtractedEntry](#filesextractedsummaryresponselanguagesextractedentry) | Language-level information about how many files were extracted |
 <!-- end Fields -->
 <!-- end HasFields -->


## FilesExtractedSummaryResponse.LanguagesExtractedEntry



| Field | Type | Description |
| ----- | ---- | ----------- |
| key | [ string](#string) | none |
| value | [ ToolStatusExtracted](#toolstatusextracted) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## GetCodeScanningEnabledRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| repository_id | [ uint64](#uint64) | none |
| default_ref_name_bytes | [ bytes](#bytes) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## GetCodeScanningEnabledResponse



| Field | Type | Description |
| ----- | ---- | ----------- |
| is_enabled | [ bool](#bool) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## GetLinksForAlertsRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| repos_and_alerts | [repeated RepoNumber](#reponumber) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## GetLinksForAlertsResponse



| Field | Type | Description |
| ----- | ---- | ----------- |
| links | [repeated AlertLink](#alertlink) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## Location



| Field | Type | Description |
| ----- | ---- | ----------- |
| file_path | [ string](#string) | none |
| start_line | [ uint32](#uint32) | none |
| end_line | [ uint32](#uint32) | none |
| start_column | [ uint32](#uint32) | none |
| end_column | [ uint32](#uint32) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## MissingCategorySummary



| Field | Type | Description |
| ----- | ---- | ----------- |
| delivery_origin | [ DeliveryOrigin](#deliveryorigin) | none |
| workflow_path | [ bytes](#bytes) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## NewCategorySummary



| Field | Type | Description |
| ----- | ---- | ----------- |
| alert_count | [ uint64](#uint64) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## OrgRule



| Field | Type | Description |
| ----- | ---- | ----------- |
| sarif_identifier | [ string](#string) | none |
| short_description | [ string](#string) | none |
| alert_count | [ uint64](#uint64) | none |
| tags | [repeated string](#string) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## OrgRuleTag



| Field | Type | Description |
| ----- | ---- | ----------- |
| tag | [ string](#string) | none |
| alert_count | [ uint64](#uint64) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## OutdatedConfiguration



| Field | Type | Description |
| ----- | ---- | ----------- |
| tool_name | [ string](#string) | none |
| category | [ string](#string) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## ProcessError



| Field | Type | Description |
| ----- | ---- | ----------- |
| error_type | [ string](#string) | none |
| message | [ string](#string) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## PullRequestAlertsRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| repository_id | [ uint64](#uint64) | none |
| tool | [ string](#string) | none |
| base_ref_bytes | [ bytes](#bytes) | none |
| head_commit_oid | [ string](#string) | none |
| merge_commit_oid | [ string](#string) | none |
| file_changes | [repeated FileChange](#filechange) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## PullRequestAlertsResponse



| Field | Type | Description |
| ----- | ---- | ----------- |
| new_alerts | [repeated DiffedAlert](#diffedalert) | none |
| new_count | [ uint64](#uint64) | none |
| security_critical_count | [ uint64](#uint64) | none |
| security_high_count | [ uint64](#uint64) | none |
| security_medium_count | [ uint64](#uint64) | none |
| security_low_count | [ uint64](#uint64) | none |
| error_count | [ uint64](#uint64) | none |
| warning_count | [ uint64](#uint64) | none |
| note_count | [ uint64](#uint64) | none |
| new_categories | [map PullRequestAlertsResponse.NewCategoriesEntry](#pullrequestalertsresponsenewcategoriesentry) | none |
| missing_categories | [map PullRequestAlertsResponse.MissingCategoriesEntry](#pullrequestalertsresponsemissingcategoriesentry) | none |
| fixed_alerts | [repeated DiffedAlert](#diffedalert) | none |
| fixed_count | [ uint64](#uint64) | none |
| latest_upload_time | [ google.protobuf.Timestamp](#googleprotobuftimestamp) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## PullRequestAlertsResponse.MissingCategoriesEntry



| Field | Type | Description |
| ----- | ---- | ----------- |
| key | [ string](#string) | none |
| value | [ MissingCategorySummary](#missingcategorysummary) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## PullRequestAlertsResponse.NewCategoriesEntry



| Field | Type | Description |
| ----- | ---- | ----------- |
| key | [ string](#string) | none |
| value | [ NewCategorySummary](#newcategorysummary) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## PullRequestIntroducedAlertsRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| repository_id | [ uint64](#uint64) | none |
| tool | [ string](#string) | none |
| base_ref_bytes | [ bytes](#bytes) | none |
| head_commit_oid | [ string](#string) | none |
| merge_commit_oid | [ string](#string) | none |
| pr_number | [ uint32](#uint32) | none |
| file_changes | [repeated FileChange](#filechange) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## PullRequestIntroducedAlertsResponse



| Field | Type | Description |
| ----- | ---- | ----------- |
| alerts | [repeated AlertInPullRequest](#alertinpullrequest) | none |
| total_count | [ uint64](#uint64) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## RelatedLocation



| Field | Type | Description |
| ----- | ---- | ----------- |
| created_at | [ google.protobuf.Timestamp](#googleprotobuftimestamp) | none |
| updated_at | [ google.protobuf.Timestamp](#googleprotobuftimestamp) | none |
| message | [ string](#string) | none |
| replacement_index | [ uint32](#uint32) | none |
| location | [ Location](#location) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## RepoResult



| Field | Type | Description |
| ----- | ---- | ----------- |
| repository_id | [ uint64](#uint64) | none |
| result | [ Result](#result) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## RepositoryIDsForOrgRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| filter | [ AlertsFilter](#alertsfilter) | none |
| owner_ids | [repeated uint64](#uint64) | none |
| repository_ids | [repeated uint64](#uint64) | none |
| excluded_repository_ids | [repeated uint64](#uint64) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## RepositoryIDsResponse



| Field | Type | Description |
| ----- | ---- | ----------- |
| repositories | [repeated RepositoryIDsResponse.Repository](#repositoryidsresponserepository) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## RepositoryIDsResponse.Repository



| Field | Type | Description |
| ----- | ---- | ----------- |
| repository_id | [ uint64](#uint64) | none |
| alert_count | [ uint64](#uint64) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## Result
A Result corresponds to a row from ts_logical_alerts
WARNING: This message is also used as part of the AlertEvent hydro schema. Any change should be synced
with: https://github.com/github/hydro-schemas/blob/master/proto/hydro/schemas/turboscan/v0/alert_event.proto


| Field | Type | Description |
| ----- | ---- | ----------- |
| message_text | [ string](#string) | none |
| rule_severity | [ RuleSeverity](#ruleseverity) | TODO: rename - this relates to a single physical alert’s severity and is usually derived from rule severity but can be different |
| created_at | [ google.protobuf.Timestamp](#googleprotobuftimestamp) | none |
| resolution | [ ResultResolution](#resultresolution) | none |
| resolver_id | [ uint32](#uint32) | none |
| resolved_at | [ google.protobuf.Timestamp](#googleprotobuftimestamp) | none |
| number | [ uint32](#uint32) | none |
| tool | [ ToolDescription](#tooldescription) | none |
| message_markdown | [ string](#string) | none |
| guid | [ string](#string) | none |
| security_severity | [ SecuritySeverity](#securityseverity) | none |
| most_recent_instance | [ AlertInstance](#alertinstance) | none |
| is_fixed | [ bool](#bool) | none |
| rule | [ Rule](#rule) | none |
| fixed_at | [ google.protobuf.Timestamp](#googleprotobuftimestamp) | none |
| updated_at | [ google.protobuf.Timestamp](#googleprotobuftimestamp) | none |
| resolution_note | [ string](#string) | none |
| dismissal_approver_id | [ uint64](#uint64) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## Rule



| Field | Type | Description |
| ----- | ---- | ----------- |
| sarif_identifier | [ string](#string) | none |
| short_description | [ string](#string) | none |
| tags | [repeated string](#string) | none |
| name | [ string](#string) | none |
| severity | [ RuleSeverity](#ruleseverity) | none |
| full_description | [ string](#string) | none |
| help | [ string](#string) | none |
| query_uri | [ string](#string) | none |
| help_uri | [ string](#string) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## RuleOrigin



| Field | Type | Description |
| ----- | ---- | ----------- |
| name | [ string](#string) | none |
| version | [ string](#string) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## RuleTagsForOrgRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| owner_ids | [repeated uint64](#uint64) | none |
| repository_ids | [repeated uint64](#uint64) | none |
| excluded_repository_ids | [repeated uint64](#uint64) | none |
| filter | [ AlertsFilter](#alertsfilter) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## RuleTagsForOrgResponse



| Field | Type | Description |
| ----- | ---- | ----------- |
| rule_tags | [repeated OrgRuleTag](#orgruletag) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## RuleTagsRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| repository_id | [ uint64](#uint64) | required |
| tools | [repeated string](#string) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## RuleTagsResponse



| Field | Type | Description |
| ----- | ---- | ----------- |
| rule_tags | [repeated string](#string) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## RulesForOrgRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| repository_ids | [repeated uint64](#uint64) | none |
| filter | [ AlertsFilter](#alertsfilter) | none |
| excluded_repository_ids | [repeated uint64](#uint64) | none |
| owner_ids | [repeated uint64](#uint64) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## RulesForOrgResponse
The rule response is different from the repo-level one as we do not have the same level
of rule detail available on the organization level


| Field | Type | Description |
| ----- | ---- | ----------- |
| rules | [repeated OrgRule](#orgrule) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## RulesRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| repository_id | [ uint64](#uint64) | required |
| tools | [repeated string](#string) | none |
| search_query | [ string](#string) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## RulesResponse



| Field | Type | Description |
| ----- | ---- | ----------- |
| rules | [repeated Rule](#rule) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## SetAlertsStatusRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| repository_id | [ uint64](#uint64) | required |
| resolution | [ ResultResolution](#resultresolution) | required |
| resolver_id | [ uint32](#uint32) | required |
| numbers | [repeated uint32](#uint32) | required |
| resolution_note | [ string](#string) | none |
| ref_names_bytes | [repeated bytes](#bytes) | none |
| resolver_login | [ string](#string) | none |
| org_id | [ uint64](#uint64) | none |
| org | [ string](#string) | none |
| business_id | [ uint64](#uint64) | none |
| business | [ string](#string) | none |
| dismissal_approver_id | [ uint64](#uint64) | none |
| dismissal_approver_login | [ string](#string) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## SetAlertsStatusResponse



| Field | Type | Description |
| ----- | ---- | ----------- |
| results | [repeated Result](#result) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## SeveritiesForOrgRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| repository_ids | [repeated uint64](#uint64) | none |
| filter | [ AlertsFilter](#alertsfilter) | none |
| excluded_repository_ids | [repeated uint64](#uint64) | none |
| owner_ids | [repeated uint64](#uint64) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## SeveritiesForOrgResponse



| Field | Type | Description |
| ----- | ---- | ----------- |
| severities | [repeated SeveritiesForOrgResponse.SeverityItem](#severitiesfororgresponseseverityitem) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## SeveritiesForOrgResponse.SeverityItem



| Field | Type | Description |
| ----- | ---- | ----------- |
| severity | [ Severity](#severity) | none |
| alert_count | [ uint64](#uint64) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## TimelineEvent



| Field | Type | Description |
| ----- | ---- | ----------- |
| id | [ uint64](#uint64) | none |
| logical_alert_id | [ uint64](#uint64) | none |
| type | [ TimelineEventType](#timelineeventtype) | none |
| message | [ string](#string) | none |
| timestamp | [ google.protobuf.Timestamp](#googleprotobuftimestamp) | none |
| commit_oid | [ string](#string) | none |
| user_id | [ uint32](#uint32) | none |
| resolution | [ ResultResolution](#resultresolution) | none |
| file_path | [ string](#string) | none |
| start_line | [ uint32](#uint32) | none |
| tool_version | [ string](#string) | none |
| environment | [repeated EnvironmentData](#environmentdata) | none |
| workflow_run_id | [ uint64](#uint64) | none |
| category | [ string](#string) | none |
| resolution_note | [ string](#string) | none |
| ref_name_bytes | [ bytes](#bytes) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## TimelineEventsRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| repository_id | [ uint64](#uint64) | none |
| number | [ uint32](#uint32) | none |
| ref_names_bytes | [repeated bytes](#bytes) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## TimelineEventsResponse



| Field | Type | Description |
| ----- | ---- | ----------- |
| events | [repeated TimelineEvent](#timelineevent) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## ToolAlertCount



| Field | Type | Description |
| ----- | ---- | ----------- |
| tool_name | [ string](#string) | none |
| open_count | [ uint64](#uint64) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## ToolDescription



| Field | Type | Description |
| ----- | ---- | ----------- |
| name | [ string](#string) | none |
| guid | [ string](#string) | none |
| version | [ string](#string) | none |
| alert_count | [ uint64](#uint64) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## ToolNamesForOrgRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| repository_ids | [repeated uint64](#uint64) | none |
| filter | [ AlertsFilter](#alertsfilter) | none |
| excluded_repository_ids | [repeated uint64](#uint64) | none |
| owner_ids | [repeated uint64](#uint64) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## ToolNamesRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| repository_id | [ uint64](#uint64) | required |
 <!-- end Fields -->
 <!-- end HasFields -->


## ToolNamesResponse



| Field | Type | Description |
| ----- | ---- | ----------- |
| tools | [repeated ToolDescription](#tooldescription) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## ToolStatus



| Field | Type | Description |
| ----- | ---- | ----------- |
| name | [ string](#string) | The name of the tool this ToolStatus record is for |
| categories | [repeated CategoryStatus](#categorystatus) | Information about the latest analysis for each category |
 <!-- end Fields -->
 <!-- end HasFields -->


## ToolStatusExtracted
ToolStatusExtracted contains aggregated information about which files were extracted during an analysis


| Field | Type | Description |
| ----- | ---- | ----------- |
| extracted | [ uint64](#uint64) | The number of files successfully extracted |
| total | [ uint64](#uint64) | The total number of files that the tool found in the repository |
 <!-- end Fields -->
 <!-- end HasFields -->


## ToolStatusRequest
Represents Tool Status page request


| Field | Type | Description |
| ----- | ---- | ----------- |
| repository_id | [ uint64](#uint64) | __(Required)__ Repository ID for retrieving Tool Status information |
| ref | [ bytes](#bytes) | Ref is the branch reference, base64 encoded

__(Required)__ |
 <!-- end Fields -->
 <!-- end HasFields -->


## ToolStatusResponse



| Field | Type | Description |
| ----- | ---- | ----------- |
| tools | [repeated ToolStatus](#toolstatus) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## ToolStatusRulesRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| repository_id | [ uint64](#uint64) | __(Required)__ Repository ID for retrieving Tool Status information. |
| ref | [ bytes](#bytes) | __(Required)__ Ref is the branch reference, base64 encoded. |
| tool | [ string](#string) | __(Required)__ The name of the tool to provide information for.

required |
| analysis_ids | [repeated uint64](#uint64) | __(Required)__ List of analyses to return rules for. |
 <!-- end Fields -->
 <!-- end HasFields -->


## ToolStatusRulesResponse



| Field | Type | Description |
| ----- | ---- | ----------- |
| categories | [map ToolStatusRulesResponse.CategoriesEntry](#toolstatusrulesresponsecategoriesentry) | Categories contains a map of analysis categories to files that were extracted. |
 <!-- end Fields -->
 <!-- end HasFields -->


## ToolStatusRulesResponse.CategoriesEntry



| Field | Type | Description |
| ----- | ---- | ----------- |
| key | [ string](#string) | none |
| value | [ ToolStatusRulesResponse.CategoryRules](#toolstatusrulesresponsecategoryrules) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## ToolStatusRulesResponse.CategoryRules



| Field | Type | Description |
| ----- | ---- | ----------- |
| origins | [repeated ToolStatusRulesResponse.CategoryRules.RuleOrigins](#toolstatusrulesresponsecategoryrulesruleorigins) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## ToolStatusRulesResponse.CategoryRules.Rule



| Field | Type | Description |
| ----- | ---- | ----------- |
| sarif_identifier | [ string](#string) | none |
| results | [ uint64](#uint64) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## ToolStatusRulesResponse.CategoryRules.RuleOrigins



| Field | Type | Description |
| ----- | ---- | ----------- |
| origin | [ RuleOrigin](#ruleorigin) | none |
| rules | [repeated ToolStatusRulesResponse.CategoryRules.Rule](#toolstatusrulesresponsecategoryrulesrule) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## TotalCountsForCampaignsRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| owner_ids | [repeated uint64](#uint64) | none |
| repository_ids | [repeated uint64](#uint64) | none |
| excluded_repository_ids | [repeated uint64](#uint64) | none |
| filter | [ AlertsFilter](#alertsfilter) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## TotalCountsForCampaignsResponse



| Field | Type | Description |
| ----- | ---- | ----------- |
| open_count | [ uint64](#uint64) | none |
| closed_count | [ uint64](#uint64) | none |
| open_with_links_count | [ uint64](#uint64) | none |
| dismissed_count | [ uint64](#uint64) | none |
| autofix_supported_count | [ uint64](#uint64) | none |
| autofix_generated_count | [ uint64](#uint64) | none |
| autofix_accepted_count | [ uint64](#uint64) | none |
 <!-- end Fields -->
 <!-- end HasFields -->
 <!-- end messages -->

# Enums


## AlertSortOrder


| Name | Number | Description |
| ---- | ------ | ----------- |
| WEIGHT | 0 | none |
| CREATED_ASCENDING | 1 | none |
| CREATED_DESCENDING | 2 | none |
| UPDATED_ASCENDING | 3 | none |
| UPDATED_DESCENDING | 4 | none |




## AnalysesSortOrder


| Name | Number | Description |
| ---- | ------ | ----------- |
| ANALYSES_CREATED_DESCENDING | 0 | none |
| ANALYSES_CREATED_ASCENDING | 1 | none |




## AnalysisMessageLevel
AnalysisMessageLevel represents how a Code Scanning status message relates to the status of a Code Scanning tool.
When aggregating tool status across multiple analyses, the highest value is taken as the overall status.

| Name | Number | Description |
| ---- | ------ | ----------- |
| SUCCESS | 0 | Messages that affirm Code Scanning worked correctly |
| ATTENTION | 1 | Code scanning worked, however the tool may be misconfigured |
| DANGER | 2 | Code scanning is not working |




## AnalysisStatus


| Name | Number | Description |
| ---- | ------ | ----------- |
| UNKNOWN | 0 | none |
| MISSING | 1 | none |
| PENDING | 2 | none |
| FAILED | 3 | none |
| COMPLETE | 4 | none |




## CategoryStatus.QuerySuite.Type


| Name | Number | Description |
| ---- | ------ | ----------- |
| QUERY_SUITE_UNKNOWN | 0 | none |
| QUERY_SUITE_BUILTIN_SUITE | 1 | none |
| QUERY_SUITE_LOCAL_QUERY | 2 | none |
| QUERY_SUITE_EXTERNAL_REPOSITORY | 3 | none |




## DeliveryOrigin


| Name | Number | Description |
| ---- | ------ | ----------- |
| DELIVERY_ORIGIN_UNKNOWN | 0 | We don't know what this is, but it could be a new enablement advanced/third-party tools setup. |
| DELIVERY_ORIGIN_YML | 1 | YML-Based analysis. The YML is available in the repo. |
| DELIVERY_ORIGIN_MANAGED | 2 | Managed Analysis. |
| DELIVERY_ORIGIN_DYNAMIC | 3 | Dynamic Actions Run (excl. Managed Analysis). |
| DELIVERY_ORIGIN_API | 4 | Analysis from API. |




## EvalRefUpdateRulesRequest.SecuritySeverityChoice


| Name | Number | Description |
| ---- | ------ | ----------- |
| SECURITY_SEVERITY_NONE | 0 | none |
| SECURITY_SEVERITY_CRITICAL | 1 | none |
| SECURITY_SEVERITY_HIGH_OR_HIGHER | 2 | none |
| SECURITY_SEVERITY_MEDIUM_OR_HIGHER | 3 | none |
| SECURITY_SEVERITY_ALL | 4 | none |




## EvalRefUpdateRulesRequest.SeverityChoice


| Name | Number | Description |
| ---- | ------ | ----------- |
| SEVERITY_NONE | 0 | none |
| SEVERITY_ERRORS | 1 | none |
| SEVERITY_ERRORS_AND_WARNINGS | 2 | none |
| SEVERITY_ALL | 3 | none |




## SearchStatus


| Name | Number | Description |
| ---- | ------ | ----------- |
| STATUS_OK | 0 | none |
| STATUS_INTERNAL_ERROR | 1 | none |
| STATUS_NOT_CONFIGURED | 2 | none |
| STATUS_INVALID_QUERY | 3 | none |




## TimelineEventType


| Name | Number | Description |
| ---- | ------ | ----------- |
| TIMELINE_EVENT_TYPE_UNKNOWN | 0 | none |
| TIMELINE_EVENT_TYPE_ALERT_APPEARED_IN_BRANCH | 1 | none |
| TIMELINE_EVENT_TYPE_ALERT_CLOSED_BECAME_FIXED | 3 | none |
| TIMELINE_EVENT_TYPE_ALERT_CLOSED_BY_USER | 4 | none |
| TIMELINE_EVENT_TYPE_ALERT_CREATED | 6 | none |
| TIMELINE_EVENT_TYPE_ALERT_REAPPEARED | 7 | none |
| TIMELINE_EVENT_TYPE_ALERT_REOPENED_BY_USER | 9 | none |
| TIMELINE_EVENT_TYPE_ALERT_DELETED_BY_USER | 10 | none |
| TIMELINE_EVENT_TYPE_ALERT_CLOSED_BECAME_OUTDATED | 11 | none |


 <!-- end Enums -->


# SuggestedFixes

SuggestedFixes service provides methods to manage suggested fixes for alerts.

## GetSuggestedFix

> **rpc** GetSuggestedFix([GetSuggestedFixRequest](#getsuggestedfixrequest))
    [GetSuggestedFixResponse](#getsuggestedfixresponse)

GetSuggestedFix returns a suggested fix for an alert.
## GenerateSuggestedFix

> **rpc** GenerateSuggestedFix([GenerateSuggestedFixRequest](#generatesuggestedfixrequest))
    [GenerateSuggestedFixResponse](#generatesuggestedfixresponse)

GenerateSuggestedFix triggers the generation of suggested fixes for the given alerts.
## ApplySuggestedFix

> **rpc** ApplySuggestedFix([ApplySuggestedFixRequest](#applysuggestedfixrequest))
    [ApplySuggestedFixResponse](#applysuggestedfixresponse)

ApplySuggestedFix marks an alert suggestion as applied
## GetSuggestedFixStatistics

> **rpc** GetSuggestedFixStatistics([GetSuggestedFixStatisticsRequest](#getsuggestedfixstatisticsrequest))
    [GetSuggestedFixStatisticsResponse](#getsuggestedfixstatisticsresponse)

GetSuggestedFixStatistics returns total suggested fixes
## GenerateDependabotFix

> **rpc** GenerateDependabotFix([GenerateDependabotFixRequest](#generatedependabotfixrequest))
    [GenerateDependabotFixResponse](#generatedependabotfixresponse)

GenerateDependabotFix triggers the generation of fixes for dependabot alerts.
## GenerateSyncFix

> **rpc** GenerateSyncFix([GenerateSyncFixRequest](#generatesyncfixrequest))
    [GenerateSyncFixResponse](#generatesyncfixresponse)

GenerateSyncFix triggers the generation of fixes using cocofix.
## GetSuggestedFixStatesForOrg

> **rpc** GetSuggestedFixStatesForOrg([GetSuggestedFixStatesForOrgRequest](#getsuggestedfixstatesfororgrequest))
    [GetSuggestedFixStatesForOrgResponse](#getsuggestedfixstatesfororgresponse)

GetSuggestedFixStatesForOrg returns the state of suggested fixes for the given org from the ES index.
 <!-- end methods -->
 <!-- end services -->

# Messages


## Advisory



| Field | Type | Description |
| ----- | ---- | ----------- |
| id | [ string](#string) | none |
| html_url | [ string](#string) | none |
| summary | [ string](#string) | none |
| description | [ string](#string) | none |
| severity | [ AdvisorySeverity](#advisoryseverity) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## ApplySuggestedFixRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| repository_id | [ uint64](#uint64) | none |
| alert_number | [ uint32](#uint32) | none |
| ref_names_bytes | [repeated bytes](#bytes) | none |
| actor_id | [ uint64](#uint64) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## ApplySuggestedFixResponse



| Field | Type | Description |
| ----- | ---- | ----------- |
| success | [ bool](#bool) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## DependencyMetadata



| Field | Type | Description |
| ----- | ---- | ----------- |
| name | [ string](#string) | none |
| version | [ string](#string) | none |
| advisories | [repeated Advisory](#advisory) | none |
| url | [ string](#string) | none |
| description | [ string](#string) | none |
| ecosystem | [ string](#string) | none |
| malicious | [ bool](#bool) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## GenerateDependabotFixRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| request_id | [ uint32](#uint32) | none |
| repository_id | [ uint64](#uint64) | none |
| commit_oid | [ string](#string) | none |
| sarif | [ string](#string) | none |
| file_paths | [repeated string](#string) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## GenerateDependabotFixResponse



| Field | Type | Description |
| ----- | ---- | ----------- |
| success | [ bool](#bool) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## GenerateSuggestedFixRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| repository_id | [ uint64](#uint64) | none |
| alert_numbers | [repeated uint32](#uint32) | the list of alerts to trigger fix generation |
| ref_names_bytes | [repeated bytes](#bytes) | none |
| pull_request_id | [ uint64](#uint64) | none |
| user_id | [ uint64](#uint64) | none |
| public | [ bool](#bool) | Indicates if the repository is public or private |
| source | [ SuggestedFixSource](#suggestedfixsource) | none |
| security_campaign_id | [ uint64](#uint64) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## GenerateSuggestedFixResponse



| Field | Type | Description |
| ----- | ---- | ----------- |
| success | [ bool](#bool) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## GenerateSyncFixRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| sarif | [ string](#string) | none |
| interaction_id | [ string](#string) | none |
| interaction_type | [ string](#string) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## GenerateSyncFixResponse



| Field | Type | Description |
| ----- | ---- | ----------- |
| suggested_fix | [ SuggestedFix](#suggestedfix) | none |
| state | [ SuggestedFixAlertState](#suggestedfixalertstate) | none |
| ai_version | [ string](#string) | none |
| ai_model | [ string](#string) | none |
| error | [ GenerateSyncFixError](#generatesyncfixerror) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## GetSuggestedFixRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| repository_id | [ uint64](#uint64) | none |
| head_commit_oid | [ string](#string) | none |
| alert_numbers | [repeated uint32](#uint32) | none |
| ref_names_bytes | [repeated bytes](#bytes) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## GetSuggestedFixResponse



| Field | Type | Description |
| ----- | ---- | ----------- |
| suggested_fix_alerts | [map GetSuggestedFixResponse.SuggestedFixAlertsEntry](#getsuggestedfixresponsesuggestedfixalertsentry) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## GetSuggestedFixResponse.SuggestedFixAlertsEntry



| Field | Type | Description |
| ----- | ---- | ----------- |
| key | [ uint32](#uint32) | none |
| value | [ SuggestedFixAlert](#suggestedfixalert) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## GetSuggestedFixStatesForOrgRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| limit | [ uint32](#uint32) | none |
| before_cursor | [ string](#string) | none |
| after_cursor | [ string](#string) | none |
| owner_ids | [repeated uint64](#uint64) | none |
| repository_ids | [repeated uint64](#uint64) | none |
| excluded_repository_ids | [repeated uint64](#uint64) | none |
| filter | [ AlertsFilter](#alertsfilter) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## GetSuggestedFixStatesForOrgResponse



| Field | Type | Description |
| ----- | ---- | ----------- |
| suggested_fix_states | [repeated RepoSuggestedFixState](#reposuggestedfixstate) | none |
| next_cursor | [ string](#string) | none |
| prev_cursor | [ string](#string) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## GetSuggestedFixStatisticsRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| owner_ids | [repeated uint64](#uint64) | none |
| repository_ids | [repeated uint64](#uint64) | none |
| severities | [repeated Severity](#severity) | none |
| start | [ google.protobuf.Timestamp](#googleprotobuftimestamp) | none |
| end | [ google.protobuf.Timestamp](#googleprotobuftimestamp) | none |
| rule_ids | [repeated string](#string) | none |
| exclude_rule_ids | [repeated string](#string) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## GetSuggestedFixStatisticsResponse



| Field | Type | Description |
| ----- | ---- | ----------- |
| suggested | [ uint64](#uint64) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## RepoSuggestedFixState



| Field | Type | Description |
| ----- | ---- | ----------- |
| repository_id | [ uint64](#uint64) | none |
| alert_number | [ uint32](#uint32) | none |
| eligible | [ bool](#bool) | none |
| state | [ SuggestedFixAlertState](#suggestedfixalertstate) | none |
| state_updated_at | [ google.protobuf.Timestamp](#googleprotobuftimestamp) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## SuggestedFix



| Field | Type | Description |
| ----- | ---- | ----------- |
| description | [ string](#string) | none |
| files | [repeated SuggestedFixFile](#suggestedfixfile) | none |
| created_at | [ google.protobuf.Timestamp](#googleprotobuftimestamp) | none |
| updated_at | [ google.protobuf.Timestamp](#googleprotobuftimestamp) | none |
| dependency_metadata | [repeated DependencyMetadata](#dependencymetadata) | none |
| outdated | [ bool](#bool) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## SuggestedFixAlert



| Field | Type | Description |
| ----- | ---- | ----------- |
| alert_number | [ uint32](#uint32) | none |
| state | [ SuggestedFixAlertState](#suggestedfixalertstate) | none |
| state_updated_at | [ google.protobuf.Timestamp](#googleprotobuftimestamp) | none |
| state_updated_actor_id | [ uint64](#uint64) | none |
| created_at | [ google.protobuf.Timestamp](#googleprotobuftimestamp) | none |
| updated_at | [ google.protobuf.Timestamp](#googleprotobuftimestamp) | none |
| suggested_fix | [ SuggestedFix](#suggestedfix) | none |
| rule_sarif_identifier | [ string](#string) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## SuggestedFixFile



| Field | Type | Description |
| ----- | ---- | ----------- |
| file_path | [ string](#string) | none |
| diff_content | [ bytes](#bytes) | none |
| created_at | [ google.protobuf.Timestamp](#googleprotobuftimestamp) | none |
| updated_at | [ google.protobuf.Timestamp](#googleprotobuftimestamp) | none |
 <!-- end Fields -->
 <!-- end HasFields -->
 <!-- end messages -->

# Enums


## AdvisorySeverity


| Name | Number | Description |
| ---- | ------ | ----------- |
| ADVISORY_SEVERITY_UNKNOWN | 0 | none |
| ADVISORY_SEVERITY_LOW | 1 | none |
| ADVISORY_SEVERITY_MEDIUM | 2 | none |
| ADVISORY_SEVERITY_HIGH | 3 | none |
| ADVISORY_SEVERITY_CRITICAL | 4 | none |




## GenerateSyncFixError


| Name | Number | Description |
| ---- | ------ | ----------- |
| GENERATE_SYNC_FIX_ERROR_NIL | 0 | none |
| GENERATE_SYNC_FIX_ERROR_TRANSIENT | 1 | none |
| GENERATE_SYNC_FIX_ERROR_NON_RETRIABLE | 2 | none |




## SuggestedFixAlertState


| Name | Number | Description |
| ---- | ------ | ----------- |
| SUGGESTED_FIX_ALERT_STATE_UNKNOWN | 0 | none |
| SUGGESTED_FIX_ALERT_STATE_APPLIED | 1 | none |
| SUGGESTED_FIX_ALERT_STATE_ERROR | 3 | none |
| SUGGESTED_FIX_ALERT_STATE_INVALID | 4 | none |
| SUGGESTED_FIX_ALERT_STATE_RULE_NOT_SUPPORTED | 5 | none |
| SUGGESTED_FIX_ALERT_STATE_PENDING | 6 | none |
| SUGGESTED_FIX_ALERT_STATE_VALID | 7 | none |
| SUGGESTED_FIX_ALERT_STATE_VALID_MISSING_DEP | 8 | none |




## SuggestedFixSource


| Name | Number | Description |
| ---- | ------ | ----------- |
| SUGGESTED_FIX_SOURCE_UNKNOWN | 0 | none |
| SUGGESTED_FIX_SOURCE_PR | 1 | none |
| SUGGESTED_FIX_SOURCE_ONDEMAND | 2 | none |
| SUGGESTED_FIX_SOURCE_SECURITY_CAMPAIGN | 3 | none |
| SUGGESTED_FIX_SOURCE_ONDEMAND_API | 4 | none |


 <!-- end Enums -->


 <!-- end services -->

# Messages


## AlertsFilter



| Field | Type | Description |
| ----- | ---- | ----------- |
| state | [ AlertStateFilter](#alertstatefilter) | none |
| search_query | [ string](#string) | none |
| excluded_rule_sarif_identifiers | [repeated string](#string) | none |
| excluded_tools | [repeated string](#string) | none |
| excluded_severities | [repeated Severity](#severity) | none |
| excluded_resolutions | [repeated ResultResolutionFilter](#resultresolutionfilter) | none |
| severities | [repeated Severity](#severity) | none |
| tools | [repeated string](#string) | none |
| tool_guids | [repeated string](#string) | none |
| rule_sarif_identifiers | [repeated string](#string) | none |
| rule_tags | [repeated string](#string) | none |
| excluded_rule_tags | [repeated string](#string) | none |
| repository_visibilities | [repeated RepositoryVisibility](#repositoryvisibility) | none |
| resolutions | [repeated ResultResolutionFilter](#resultresolutionfilter) | none |
| classification | [ AlertClassificationFilter](#alertclassificationfilter) | none |
| alert_links | [ AlertLinksFilter](#alertlinksfilter) | none |
| autofix | [ AutofixFilter](#autofixfilter) | none |
| repo_numbers | [repeated RepoNumber](#reponumber) | none |
| autofixes | [repeated AutofixFilter](#autofixfilter) | none |
| excluded_autofixes | [repeated AutofixFilter](#autofixfilter) | none |
| security_campaign_ids | [repeated uint64](#uint64) | none |
| excluded_security_campaign_ids | [repeated uint64](#uint64) | none |
| campaign_presence | [ CampaignPresenceFilter](#campaignpresencefilter) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## RepoNumber



| Field | Type | Description |
| ----- | ---- | ----------- |
| repository_id | [ uint64](#uint64) | none |
| number | [ uint32](#uint32) | none |
 <!-- end Fields -->
 <!-- end HasFields -->
 <!-- end messages -->

# Enums


## AlertClassificationFilter


| Name | Number | Description |
| ---- | ------ | ----------- |
| ALERT_CLASSIFICATION_FILTER_NO_FILTER | 0 | none |
| ALERT_CLASSIFICATION_FILTER_UNCLASSIFIED | 1 | none |
| ALERT_CLASSIFICATION_FILTER_ANY_CLASSIFICATION | 2 | none |




## AlertLinksFilter


| Name | Number | Description |
| ---- | ------ | ----------- |
| ALERT_LINKS_FILTER_NO_FILTER | 0 | none |
| ALERT_LINKS_FILTER_NO_LINKS | 1 | none |
| ALERT_LINKS_FILTER_ANY_LINKS | 2 | none |




## AlertStateFilter


| Name | Number | Description |
| ---- | ------ | ----------- |
| ALERT_STATE_FILTER_NONE | 0 | none |
| ALERT_STATE_FILTER_ALL | 1 | none |
| ALERT_STATE_FILTER_OPEN | 2 | none |
| ALERT_STATE_FILTER_CLOSED | 3 | none |
| ALERT_STATE_FILTER_CLOSED_RESOLVED | 4 | none |
| ALERT_STATE_FILTER_CLOSED_FIXED | 5 | none |




## AutofixFilter


| Name | Number | Description |
| ---- | ------ | ----------- |
| AUTOFIX_FILTER_NO_FILTER | 0 | none |
| AUTOFIX_FILTER_SUPPORTED | 1 | none |
| AUTOFIX_FILTER_GENERATED | 2 | none |
| AUTOFIX_FILTER_ACCEPTED | 3 | none |




## CampaignPresenceFilter


| Name | Number | Description |
| ---- | ------ | ----------- |
| CAMPAIGN_PRESENCE_NO_FILTER | 0 | none |
| CAMPAIGN_PRESENCE_IN_CAMPAIGN | 1 | none |
| CAMPAIGN_PRESENCE_NOT_IN_CAMPAIGN | 2 | none |




## RepositoryVisibility


| Name | Number | Description |
| ---- | ------ | ----------- |
| REPOSITORY_VISIBILITY_UNKNOWN | 0 | none |
| REPOSITORY_VISIBILITY_PUBLIC | 1 | none |
| REPOSITORY_VISIBILITY_PRIVATE | 2 | none |
| REPOSITORY_VISIBILITY_INTERNAL | 3 | none |




## ResultResolution


| Name | Number | Description |
| ---- | ------ | ----------- |
| NO_RESOLUTION | 0 | none |
| FALSE_POSITIVE | 1 | none |
| WONT_FIX | 2 | none |
| USED_IN_TESTS | 3 | none |




## ResultResolutionFilter


| Name | Number | Description |
| ---- | ------ | ----------- |
| FILTER_NONE | 0 | none |
| FILTER_NO_RESOLUTION | 1 | none |
| FILTER_FALSE_POSITIVE | 2 | none |
| FILTER_WONT_FIX | 3 | none |
| FILTER_USED_IN_TESTS | 4 | none |




## RuleSeverity


| Name | Number | Description |
| ---- | ------ | ----------- |
| NONE | 0 | none |
| NOTE | 1 | none |
| WARNING | 2 | none |
| ERROR | 3 | none |




## SecuritySeverity


| Name | Number | Description |
| ---- | ------ | ----------- |
| NO_SECURITY_SEVERITY | 0 | none |
| LOW | 1 | none |
| MEDIUM | 2 | none |
| HIGH | 3 | none |
| CRITICAL | 4 | none |




## Severity
This represents a combined rule and security severity

| Name | Number | Description |
| ---- | ------ | ----------- |
| NO_SEVERITY | 0 | none |
| SEVERITY_NOTE | 1 | Rule severities |
| SEVERITY_WARNING | 2 | none |
| SEVERITY_ERROR | 3 | none |
| SEVERITY_LOW | 4 | Security severity |
| SEVERITY_MEDIUM | 5 | none |
| SEVERITY_HIGH | 6 | none |
| SEVERITY_CRITICAL | 7 | none |


 <!-- end Enums -->
 <!-- end Files -->

# Scalar Value Types

| .proto Type | Notes | Go Type | Ruby Type |
| ----------- | ----- | -------- | --------- |
| <div><h4 id="double" /></div><a name="double" /> double |  | float64 | Float |
| <div><h4 id="float" /></div><a name="float" /> float |  | float32 | Float |
| <div><h4 id="int32" /></div><a name="int32" /> int32 | Uses variable-length encoding. Inefficient for encoding negative numbers – if your field is likely to have negative values, use sint32 instead. | int32 | Bignum or Fixnum (as required) |
| <div><h4 id="int64" /></div><a name="int64" /> int64 | Uses variable-length encoding. Inefficient for encoding negative numbers – if your field is likely to have negative values, use sint64 instead. | int64 | Bignum |
| <div><h4 id="uint32" /></div><a name="uint32" /> uint32 | Uses variable-length encoding. | uint32 | Bignum or Fixnum (as required) |
| <div><h4 id="uint64" /></div><a name="uint64" /> uint64 | Uses variable-length encoding. | uint64 | Bignum or Fixnum (as required) |
| <div><h4 id="sint32" /></div><a name="sint32" /> sint32 | Uses variable-length encoding. Signed int value. These more efficiently encode negative numbers than regular int32s. | int32 | Bignum or Fixnum (as required) |
| <div><h4 id="sint64" /></div><a name="sint64" /> sint64 | Uses variable-length encoding. Signed int value. These more efficiently encode negative numbers than regular int64s. | int64 | Bignum |
| <div><h4 id="fixed32" /></div><a name="fixed32" /> fixed32 | Always four bytes. More efficient than uint32 if values are often greater than 2^28. | uint32 | Bignum or Fixnum (as required) |
| <div><h4 id="fixed64" /></div><a name="fixed64" /> fixed64 | Always eight bytes. More efficient than uint64 if values are often greater than 2^56. | uint64 | Bignum |
| <div><h4 id="sfixed32" /></div><a name="sfixed32" /> sfixed32 | Always four bytes. | int32 | Bignum or Fixnum (as required) |
| <div><h4 id="sfixed64" /></div><a name="sfixed64" /> sfixed64 | Always eight bytes. | int64 | Bignum |
| <div><h4 id="bool" /></div><a name="bool" /> bool |  | bool | TrueClass/FalseClass |
| <div><h4 id="string" /></div><a name="string" /> string | A string must always contain UTF-8 encoded or 7-bit ASCII text. | string | String (UTF-8) |
| <div><h4 id="bytes" /></div><a name="bytes" /> bytes | May contain any arbitrary sequence of bytes. | []byte | String (ASCII-8BIT) |

