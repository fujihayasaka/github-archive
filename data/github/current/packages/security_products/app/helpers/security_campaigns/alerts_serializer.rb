# typed: strict
# frozen_string_literal: true

module SecurityCampaigns
  module AlertsSerializer
    extend T::Helpers
    extend T::Sig

    requires_ancestor { ApplicationController }

    include CodeScanningHelper
    include ScanningHelper
    include RepositoriesSerializer
    sig do
      params(
        security_campaign: SecurityCampaign,
        alerts: T::Enumerable[CampaignWithAlerts::TurboscanAlert],
        repositories: T::Hash[Integer, Repository],
        suggested_fixes: T::Hash[Integer, Turboscan::Proto::SuggestedFix],
        alert_links: CodeScanning::AlertLinks,
      ).returns(
        T::Array[T::Hash[Symbol, T.untyped]]
      )
    end
    def serialized_alerts(security_campaign:, alerts:, repositories:, suggested_fixes:, alert_links:)
      alerts.map do |alert|
        repository = repositories[alert.repository_id]
        # This could happen in very rare cases where the repository disappeared while we fetched the alerts,
        # or if turboscan would return data for different repos than we requested
        next unless repository

        alert_links_for_alert = alert_links.get_links(repo_id: alert.repository_id, alert_number: alert.number)

        pull_request_links, branch_links = alert_links_for_alert.partition do |alert_link|
          alert_link.pull_request.present?
        end

        {
          number: alert.number,
          title: result_title(alert),
          ruleSeverity: alert.rule_severity.to_s.downcase,
          securitySeverity: if alert.security_severity == :NO_SECURITY_SEVERITY
                              nil
                            else
                              alert.security_severity.downcase
                            end,
          toolName: alert.tool.name,
          truncatedPath: reverse_truncate_path(alert.most_recent_instance.location.file_path, 24),
          startLine: alert.most_recent_instance.location.start_line,
          createdAt: alert.created_at.to_time.utc.xmlschema,
          isFixed: alert.is_fixed,
          isDismissed: result_resolved?(alert),
          hasSuggestedFix: suggested_fixes.has_key?(alert.number),
          campaignPath: repository_security_campaign_path(repository:, user_id: repository.owner_display_login, number: security_campaign.number),
          repository: serialized_repository(repository:),
          linkedPullRequests: pull_request_links.filter_map do |alert_link|
            pull_request = T.must(alert_link.pull_request)

            {
              number: pull_request.number,
              path: gh_show_pull_request_path(pull_request),
              title: pull_request.title,
              state: pull_request.issue&.state,
              createdAt: pull_request.created_at&.xmlschema,
              closedAt: pull_request.closed_at&.xmlschema,
              mergedAt: pull_request.merged_at&.xmlschema,
              draft: pull_request.draft?,
            }
          end,
          linkedBranches: branch_links.filter_map do |alert_link|
            next unless alert_link.branch.present?

            branch = repository.heads.find(alert_link.branch)
            next unless branch&.exist?

            {
              name: branch.name_for_display,
              path: tree_path("", branch.name, repository),
            }
          end,
        }
      end.compact
    end
  end
end
