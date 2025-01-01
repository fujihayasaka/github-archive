# typed: strict
# frozen_string_literal: true

module SecurityCampaigns
  module AlertsSerializer
    extend T::Helpers

    requires_ancestor { ApplicationController }

    include CodeScanningHelper
    include ScanningHelper
    include RepositoriesSerializer
    sig do
      params(
        security_campaign: SecurityCampaign,
        alerts: T::Enumerable[CodeScanning::AlertResult],
        suggested_fixes: T::Hash[Integer, Turboscan::Proto::SuggestedFix],
        alert_links: CodeScanning::AlertLinks,
      ).returns(
        T::Array[T::Hash[Symbol, T.untyped]]
      )
    end
    def serialized_alerts(security_campaign:, alerts:, suggested_fixes:, alert_links:)
      alerts.map do |alert|
        alert_links_for_alert = alert_links.get_links(repo_id: T.must(alert.repository.id), alert_number: alert.result.number)

        pull_request_links, branch_links = alert_links_for_alert.partition do |alert_link|
          alert_link.pull_request.present?
        end

        security_severity = alert.result.security_severity
        security_severity = Turboscan::Proto::SecuritySeverity.lookup(security_severity) if security_severity.is_a?(Integer)

        {
          number: alert.result.number,
          title: result_title(alert.result),
          ruleSeverity: alert.result.rule_severity.to_s.downcase,
          securitySeverity: if security_severity == :NO_SECURITY_SEVERITY
                              nil
                            else
                              security_severity&.downcase
                            end,
          toolName: alert.result.tool&.name,
          truncatedPath: reverse_truncate_path(alert.result.most_recent_instance&.location&.file_path, 24),
          startLine: alert.result.most_recent_instance&.location&.start_line,
          createdAt: alert.result.created_at&.to_time.utc.xmlschema,
          isFixed: alert.result.is_fixed,
          fixedAt: alert.result.fixed_at&.to_time&.utc&.xmlschema,
          isDismissed: result_resolved?(alert.result),
          dismissedAt: alert.result.resolved_at&.to_time&.utc&.xmlschema,
          resolution: alert.result.resolution,
          hasSuggestedFix: suggested_fixes.has_key?(alert.result.number),
          campaignPath: repository_security_campaign_path(repository: alert.repository, user_id: alert.repository.owner_display_login, number: security_campaign.number),
          repository: serialized_repository(repository: alert.repository),
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

            branch = alert.repository.heads.find(alert_link.branch)
            next unless branch&.exist?

            {
              name: branch.name_for_display,
              path: tree_path("", branch.name, alert.repository),
            }
          end,
        }
      end.compact
    end
  end
end
