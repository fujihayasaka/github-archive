# typed: strict
# frozen_string_literal: true

module CodeScanning
  module AlertsSerializer
    extend T::Helpers

    requires_ancestor { ApplicationController }

    include CodeScanningHelper
    include ScanningHelper

    sig do
      params(
        alerts: T::Enumerable[CodeScanning::AlertResult],
        suggested_fixes: T.nilable(T::Hash[Integer, Turboscan::Proto::SuggestedFix]),
        alert_links: T.nilable(CodeScanning::AlertLinks),
      ).returns(
        T::Array[T::Hash[Symbol, T.untyped]]
      )
    end
    def serialized_alerts(alerts:, suggested_fixes: nil, alert_links: nil)
      alerts.map do |alert|
        security_severity = alert.result.security_severity
        security_severity = Turboscan::Proto::SecuritySeverity.lookup(security_severity) if security_severity.is_a?(Integer)

        hash = {
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
          repository: serialized_repository(repository: alert.repository),
        }

        hash[:hasSuggestedFix] = suggested_fixes.has_key?(alert.result.number) unless suggested_fixes.nil?

        unless alert_links.nil?
          alert_links_for_alert = alert_links.get_links(repo_id: alert.repository.id, alert_number: alert.result.number)

          pull_request_links, branch_links = alert_links_for_alert.partition do |alert_link|
            alert_link.pull_request.present?
          end

          hash[:linkedPullRequests] = pull_request_links.filter_map do |alert_link|
            pull_request = T.must(alert_link.pull_request)

            {
              number: pull_request.number,
              title: pull_request.title,
              state: pull_request.issue&.state,
              createdAt: pull_request.created_at&.xmlschema,
              closedAt: pull_request.closed_at&.xmlschema,
              mergedAt: pull_request.merged_at&.xmlschema,
              draft: pull_request.draft?,
            }
          end

          hash[:linkedBranches] = branch_links.filter_map do |alert_link|
            branch = alert_link.branch
            next unless branch.present?

            {
              name: branch.name_for_display,
            }
          end
        end

        hash
      end
    end

    sig { params(repository: Repository).returns(T::Hash[Symbol, T.untyped]) }
    def serialized_repository(repository:)
      {
        ownerLogin: repository.owner_display_login,
        name: repository.name,
        typeIcon: repository.repo_type_icon,
      }
    end
  end
end
