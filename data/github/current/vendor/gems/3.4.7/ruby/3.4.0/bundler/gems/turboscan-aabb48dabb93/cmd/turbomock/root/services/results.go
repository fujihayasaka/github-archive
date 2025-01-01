// Package services contains mock implementations of Turboscan services.
package services

import (
	"context"
	"time"

	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/github/turboscan/cmd/turbomock/data"
	"github.com/github/turboscan/ts/proto"
)

type AlertLinks struct {
	Pr     bool
	Branch bool
}

type ResultsResponses struct {
	alertLinks AlertLinks
}

func (r *ResultsResponses) GetCounts(ctx context.Context, _ *proto.CountsRequest) (resp *proto.CountsResponse, err error) {
	resp, err = data.LoadCassette(ctx, "counts-present.yml", resp)
	resp.LatestAnalysis = timestamppb.Now()
	return
}

func (r *ResultsResponses) ToolNames(ctx context.Context, _ *proto.ToolNamesRequest) (resp *proto.ToolNamesResponse, err error) {
	return data.LoadCassette(ctx, "tool-names.yml", resp)
}

func (r *ResultsResponses) GetAlerts(ctx context.Context, req *proto.AlertsRequest) (resp *proto.AlertsResponse, err error) {
	if req.ResolvedOnly {
		return data.LoadCassette(ctx, "get-alerts-state-filter-closed.yml", resp)
	}
	if req.FilePaths != nil {
		return data.LoadCassette(ctx, "get-alerts-path-filter.yml", resp)
	}
	if len(req.Numbers) > 0 {
		if req.State == proto.AlertStateFilter_ALERT_STATE_FILTER_ALL {
			return data.LoadCassette(ctx, "get-alerts-numbers-filter-all.yml", resp)
		}
		return data.LoadCassette(ctx, "get-alerts-numbers-filter.yml", resp)
	}
	return data.LoadCassette(ctx, "get-alerts-state-filter-open.yml", resp)
}

func (r *ResultsResponses) GetAlert(ctx context.Context, req *proto.AlertRequest) (resp *proto.AlertResponse, err error) {
	if req.Number == 2 {
		return data.LoadCassette(ctx, "get-alert-2.yml", resp)
	}
	return data.LoadCassette(ctx, "get-alert.yml", resp)
}

func (r *ResultsResponses) GetToolStatus(ctx context.Context, _ *proto.ToolStatusRequest) (resp *proto.ToolStatusResponse, err error) {
	resp, err = data.LoadCassette(ctx, "get-tool-status.yml", resp)
	for _, tool := range resp.Tools {
		for _, category := range tool.Categories {
			category.UpdatedAt = timestamppb.New(time.Now().Add(-4 * time.Hour))
			category.CreatedAt = timestamppb.New(time.Now().Add(-4389 * time.Hour))
		}
	}
	return
}

func (r *ResultsResponses) GetFilesExtracted(ctx context.Context, _ *proto.FilesExtractedRequest) (resp *proto.FilesExtractedResponse, err error) {
	return data.LoadCassette(ctx, "get-extracted-files-with-messages.yml", resp)
}

func (r *ResultsResponses) GetFilesExtractedSummary(ctx context.Context, _ *proto.FilesExtractedSummaryRequest) (resp *proto.FilesExtractedSummaryResponse, err error) {
	return data.LoadCassette(ctx, "get-extracted-files-summary.yml", resp)
}

func (r *ResultsResponses) GetToolStatusRules(ctx context.Context, _ *proto.ToolStatusRulesRequest) (resp *proto.ToolStatusRulesResponse, err error) {
	return data.LoadCassette(ctx, "get-tool-status-rules.yml", resp)
}

func (r *ResultsResponses) GetAnalysis(ctx context.Context, request *proto.AnalysisRequest) (resp *proto.AnalysisResponse, err error) {
	return data.LoadCassette(ctx, "get-analysis.yml", resp)
}

func (r *ResultsResponses) GetAnalysisSarif(ctx context.Context, request *proto.AnalysisSarifRequest) (resp *proto.AnalysisSarifResponse, err error) {
	return data.LoadCassette(ctx, "analysis-sarif.yml", resp)
}

func (r *ResultsResponses) GetAnalyses(ctx context.Context, request *proto.AnalysesRequest) (resp *proto.AnalysesResponse, err error) {
	return data.LoadCassette(ctx, "get-analyses.yml", resp)
}

func (r *ResultsResponses) GetAlertTitles(ctx context.Context, request *proto.AlertTitlesRequest) (resp *proto.AlertTitlesResponse, err error) {
	return data.LoadCassette(ctx, "alert-titles.yml", resp)
}

func (r *ResultsResponses) GetCountsByTool(ctx context.Context, request *proto.CountsByToolRequest) (resp *proto.CountsByToolResponse, err error) {
	return data.LoadCassette(ctx, "counts-by-tool.yml", resp)
}

func (r *ResultsResponses) GetCodePaths(ctx context.Context, request *proto.CodePathsRequest) (resp *proto.CodePathsResponse, err error) {
	return data.LoadCassette(ctx, "get-code-paths.yml", resp)
}

func (r *ResultsResponses) GetRuleTags(ctx context.Context, request *proto.RuleTagsRequest) (resp *proto.RuleTagsResponse, err error) {
	return data.LoadCassette(ctx, "get-rule-tags.yml", resp)
}

func (r *ResultsResponses) GetRules(ctx context.Context, request *proto.RulesRequest) (resp *proto.RulesResponse, err error) {
	return data.LoadCassette(ctx, "rules.yml", resp)
}

func (r *ResultsResponses) GetTimelineEvents(ctx context.Context, request *proto.TimelineEventsRequest) (resp *proto.TimelineEventsResponse, err error) {
	return data.LoadCassette(ctx, "get-timeline-events.yml", resp)
}

func (r *ResultsResponses) PullRequestAlerts(ctx context.Context, request *proto.PullRequestAlertsRequest) (resp *proto.PullRequestAlertsResponse, err error) {
	return data.LoadCassette(ctx, "reflected-xss-pr-alerts.yml", resp)
}

func (r *ResultsResponses) PullRequestIntroducedAlerts(ctx context.Context, request *proto.PullRequestIntroducedAlertsRequest) (resp *proto.PullRequestIntroducedAlertsResponse, err error) {
	return data.LoadCassette(ctx, "pr-introduced-alerts.yml", resp)
}

func (r *ResultsResponses) Annotations(ctx context.Context, request *proto.AnnotationsRequest) (resp *proto.AnnotationsResponse, err error) {
	resp, err = data.LoadCassette(ctx, "reflected-xss-pr-alerts.yml", resp)
	if err == nil {
		resp.Results[0].Result.Number = request.Numbers[0]
	}
	return
}

func (r *ResultsResponses) SetAlertsStatus(ctx context.Context, request *proto.SetAlertsStatusRequest) (resp *proto.SetAlertsStatusResponse, err error) {
	return data.LoadCassette(ctx, "set-status-close.yml", resp)
}

func (r *ResultsResponses) DeleteAnalysis(ctx context.Context, request *proto.DeleteAnalysisRequest) (resp *proto.DeleteAnalysisResponse, err error) {
	return data.LoadCassette(ctx, "delete-analysis-confirm.yml", resp)
}

func (r *ResultsResponses) GetAlertInstances(ctx context.Context, request *proto.AlertInstancesRequest) (resp *proto.AlertInstancesResponse, err error) {
	return data.LoadCassette(ctx, "get-alert.yml", resp)
}

func (r *ResultsResponses) GetDelivery(ctx context.Context, request *proto.DeliveryRequest) (resp *proto.DeliveryResponse, err error) {
	return data.LoadCassette(ctx, "delivery-no-error.yml", resp)
}

func (r *ResultsResponses) GetAlertsByRepo(ctx context.Context, request *proto.AlertsByRepoRequest) (resp *proto.AlertsByRepoResponse, err error) {
	resp, err = data.LoadCassette(ctx, "org-alerts.yml", resp)
	if len(request.RepositoryIds) > 0 {
		// Assign each returned alerts to one of the repos in the request
		for i, result := range resp.Results {
			result.RepositoryId = request.RepositoryIds[i%len(request.RepositoryIds)]
		}
	} else {
		for _, result := range resp.Results {
			result.RepositoryId = 1
		}
	}
	return
}

func (r *ResultsResponses) GetToolNamesForOrg(ctx context.Context, request *proto.ToolNamesForOrgRequest) (resp *proto.ToolNamesResponse, err error) {
	return data.LoadCassette(ctx, "org-tools.yml", resp)
}

func (r *ResultsResponses) GetRulesForOrg(ctx context.Context, request *proto.RulesForOrgRequest) (resp *proto.RulesForOrgResponse, err error) {
	return data.LoadCassette(ctx, "org-rules.yml", resp)
}

func (r *ResultsResponses) GetRepositoryIDsForOrg(ctx context.Context, request *proto.RepositoryIDsForOrgRequest) (resp *proto.RepositoryIDsResponse, err error) {
	return data.LoadCassette(ctx, "org-repositories.yml", resp)
}

func (r *ResultsResponses) GetSeveritiesForOrg(ctx context.Context, request *proto.SeveritiesForOrgRequest) (resp *proto.SeveritiesForOrgResponse, err error) {
	return data.LoadCassette(ctx, "org-severities.yml", resp)
}

func (r *ResultsResponses) GetRuleTagsForOrg(ctx context.Context, request *proto.RuleTagsForOrgRequest) (resp *proto.RuleTagsForOrgResponse, err error) {
	return data.LoadCassette(ctx, "org-rule-tags.yml", resp)
}

func (r *ResultsResponses) GetCountsByRepo(ctx context.Context, request *proto.CountsByRepoRequest) (resp *proto.CountsByRepoResponse, err error) {
	return data.LoadCassette(ctx, "org-counts-by-repo.yml", resp)
}

func (r *ResultsResponses) CreateDelivery(ctx context.Context, request *proto.CreateDeliveryRequest) (resp *proto.CreateDeliveryResponse, err error) {
	return data.LoadCassette(ctx, "create-delivery.yml", resp)
}

func (r *ResultsResponses) GetCodeScanningEnabled(ctx context.Context, req *proto.GetCodeScanningEnabledRequest) (resp *proto.GetCodeScanningEnabledResponse, err error) {
	return data.LoadCassette(ctx, "get-code-scanning-enabled-true.yml", resp)
}

func (r *ResultsResponses) EvalRefUpdateRules(ctx context.Context, req *proto.EvalRefUpdateRulesRequest) (resp *proto.EvalRefUpdateRulesResponse, err error) {
	return data.LoadCassette(ctx, "eval-ref-update-rules-pass1.yml", resp)
}

func (r *ResultsResponses) GetCountsByCampaigns(ctx context.Context, req *proto.CountsByCampaignsRequest) (resp *proto.CountsByCampaignsResponse, err error) {
	resp, err = data.LoadCassette(ctx, "counts-by-campaigns.yml", resp)
	if len(req.SecurityCampaignIds) > 0 {
		// Loop over req.SecurityCampaignIds in the req and assign the counts to them
		for _, campaignId := range req.SecurityCampaignIds {
			resp.CampaignCounts = append(resp.CampaignCounts, &proto.CountsByCampaignsResponse_CampaignCounts{
				CampaignId:         campaignId,
				OpenCount:          8,
				ClosedCount:        1,
				OpenWithLinksCount: 2,
			})
		}
	}
	return
}

func (r *ResultsResponses) GetTotalCountsForCampaigns(ctx context.Context, req *proto.TotalCountsForCampaignsRequest) (resp *proto.TotalCountsForCampaignsResponse, err error) {
	return data.LoadCassette(ctx, "total-counts-for-campaigns.yml", resp)
}

func (r *ResultsResponses) GetLinksForAlerts(ctx context.Context, req *proto.GetLinksForAlertsRequest) (resp *proto.GetLinksForAlertsResponse, err error) {
	links := []*proto.AlertLink{}
	if r.alertLinks.Pr {
		links = append(links, &proto.AlertLink{
			AlertNumber:   req.ReposAndAlerts[0].Number,
			PullRequestId: 1,
			RepositoryId:  req.ReposAndAlerts[0].RepositoryId,
		})
	}
	if r.alertLinks.Branch {
		links = append(links, &proto.AlertLink{
			AlertNumber: req.ReposAndAlerts[0].Number,
			// repos created with the code scanning seed data are guaranteed to have a branch named pr_baseline_missing
			RefNameBytes: []byte("pr_baseline_missing"),
			RepositoryId: req.ReposAndAlerts[0].RepositoryId,
		})
	}
	return &proto.GetLinksForAlertsResponse{
		Links: links,
	}, nil
}

func (r *ResultsResponses) CreateAlertLinks(ctx context.Context, req *proto.CreateAlertLinksRequest) (resp *proto.CreateAlertLinksResponse, err error) {
	for _, link := range req.Links {
		if link.PullRequestId != 0 {
			r.alertLinks.Pr = true
		}
		if len(link.RefNameBytes) > 0 {
			r.alertLinks.Branch = true
		}
	}
	return &proto.CreateAlertLinksResponse{}, nil
}

func (r *ResultsResponses) CreateSecurityCampaignAlerts(ctx context.Context, req *proto.CreateSecurityCampaignAlertsRequest) (resp *proto.CreateSecurityCampaignAlertsResponse, err error) {
	return &proto.CreateSecurityCampaignAlertsResponse{}, nil
}

func (r *ResultsResponses) DeleteSecurityCampaignAlerts(ctx context.Context, req *proto.DeleteSecurityCampaignAlertsRequest) (resp *proto.DeleteSecurityCampaignAlertsResponse, err error) {
	return &proto.DeleteSecurityCampaignAlertsResponse{}, nil
}

func (r *ResultsResponses) GetAlertConfigurationStatuses(ctx context.Context, req *proto.AlertConfigurationStatusesRequest) (resp *proto.AlertConfigurationStatusesResponse, err error) {
	return &proto.AlertConfigurationStatusesResponse{}, nil
}

func (r *ResultsResponses) DeleteAlertLinks(ctx context.Context, req *proto.DeleteAlertLinksRequest) (resp *proto.DeleteAlertLinksResponse, err error) {
	for _, link := range req.Links {
		if link.PullRequestId != 0 {
			r.alertLinks.Pr = false
		}
		if len(link.RefNameBytes) > 0 {
			r.alertLinks.Branch = false
		}
	}
	return &proto.DeleteAlertLinksResponse{}, nil
}
