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
      assignee_ids = alerts.map(&:result).flat_map(&:assigned_user_ids)
      assignees_by_id = T.let(if assignee_ids.present?
                                User.where(id: assignee_ids).index_by(&:id)
                              else
                                {}
                              end, T::Hash[Integer, User])
      bot_ids = assignees_by_id.values.select { |user| user.is_a?(Bot) }.map(&:id)
      # Retrieve bots separately because we need to retrieve the integration without incurring N+1 queries
      bots_by_id = T.let(if bot_ids.present?
                           Bot.includes(integration: :owner).where(id: bot_ids).index_by(&:id)
                         else
                           {}
                         end, T::Hash[Integer, Bot])

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
          assignees: alert.result.assigned_user_ids.filter_map do |user_id|
            user = bots_by_id[user_id] || assignees_by_id[user_id]
            next if user.nil?
            serialized_assignee(user)
          end,
          trackingLinks: serialized_alert_tracking_links(alert.result.tracking_links),
        }

        unless suggested_fixes.nil?
          suggested_fix = suggested_fixes[alert.result.number]

          hash[:hasSuggestedFix] = suggested_fix.present?
        end

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
        defaultBranch: repository.default_branch,
      }
    end

    sig { params(user: User).returns(T::Hash[Symbol, T.untyped]) }
    def serialized_assignee(user)
      is_copilot = user.is_a?(Bot) && user.integration.present? && Apps::Privileged.capable?(:is_copilot, app: user.integration)
      profile_path = if user.is_a?(Bot)
        user.integration&.public_app_path
      else
        "/#{user.display_login}"
      end

      login = if user.is_a?(Bot)
        user.slug
      else
        user.display_login
      end

      {
        id: user.id,
        login:,
        name: user.display_name,
        avatarUrl: user.primary_avatar_url(64),
        profilePath: profile_path,
        isCopilot: is_copilot,
      }
    end

    sig { params(issue: Issue).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    def serialized_issue(issue)
      repository = issue.repository
      return nil if repository.nil?

      {
        id: issue.id,
        nodeId: issue.global_relay_id,
        number: issue.number,
        repository: serialized_repository(repository:),
        state: issue.state,
        stateReason: issue.state_reason,
        title: issue.title,
        url: issue.url,
      }
    end

    sig { params(alert_tracking_link: Turboscan::Proto::AlertTrackingLink, issue: Issue).returns(T::Hash[Symbol, T.untyped]) }
    def serialized_alert_tracking_link(alert_tracking_link, issue)
      tracking_system = ALERT_TRACKING_SYSTEM[alert_tracking_link.tracking_system]

      {
        trackingSystem: tracking_system,
        issue: serialized_issue(issue),
        trackingUrl: alert_tracking_link.tracking_url.presence,
      }
    end

    sig { params(alert_tracking_links: T::Enumerable[Turboscan::Proto::AlertTrackingLink]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def serialized_alert_tracking_links(alert_tracking_links)
      issue_ids = alert_tracking_links.map(&:issue_id).select { |id| id > 0 }

      readable_issues_by_id = Promise.all(Issue.where(id: issue_ids).map do |issue|
        issue.async_readable_by?(current_user).then { |is_readable| is_readable ? issue : nil }
      end).sync.compact.index_by(&:id)

      alert_tracking_links.filter_map do |alert_tracking_link|
        issue = readable_issues_by_id[alert_tracking_link.issue_id]
        next if issue.nil?

        serialized_alert_tracking_link(alert_tracking_link, issue)
      end
    end
  end
end
