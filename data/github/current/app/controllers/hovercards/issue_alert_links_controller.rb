# typed: true
# frozen_string_literal: true

class Hovercards::IssueAlertLinksController < AbstractRepositoryController
  include Hovercards::ConditionalAccessMethods
  include CodeScanningHelper

  before_action :require_issues_alerts_viewable
  before_action :require_xhr

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    only: [:code_scanning_alert]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Iam,
    only: [:tracked_in]

  def tracked_in # rubocop:todo GitHub/UseRestfulActions

    displayable_tracking_issues = IssueAlertLink.displayable_tracking_issues(repository: current_repository, alert_number: alert_number, viewer: current_user)

    return render_404 unless displayable_tracking_issues.present?

    render "hovercards/issue_links/tracked_in",
      locals: {
        normalized_tracking_issues: displayable_tracking_issues.map do |tracked_issue|
          {
            owner: tracked_issue.repository.owner_display_login,
            repository: tracked_issue.repository.name,
            issue_title: tracked_issue.title,
            issue_number: tracked_issue.number,
            issue_url: tracked_issue.url,
            issue_state: tracked_issue.state,
            issue_state_reason: tracked_issue.state_reason,
          }
        end,
        this_repository: current_repository
      },
      layout: false
  end

  def code_scanning_alert # rubocop:todo GitHub/UseRestfulActions

    alert = GitHub::Turboscan.alert(
      repository_id: current_repository.id,
      number: alert_number,
    )&.data&.result

    return render_404 unless alert.present?

    render "hovercards/security/alert",
      locals: {
        repository: current_repository,
        alert_filepath: alert.most_recent_instance&.location&.file_path,
        alert_path: repository_code_scanning_result_path(current_repository.owner, current_repository, number: alert_number),
        title: alert.rule&.short_description.present? ? alert.rule&.short_description : result_message_text(alert),
        description: alert.rule&.full_description,
        rule_severity: alert.rule&.severity,
        security_severity: alert.security_severity,
        created_at: alert.created_at,
      },
      layout: false
  end

  def target_type # rubocop:todo GitHub/UseRestfulActions
    # Needed by Hovercards::ConditionalAccessMethods to display in the error message when hovercard is being viewed from a non-allowed IP address.
    "code scanning alert"
  end

  private

  def require_issues_alerts_viewable
    render_404 unless (
      alert_number.present? && alert_number > 0 &&
      current_repository&.issues_alerts_integration_enabled? &&
      current_repository&.code_scanning_readable_by?(current_user)
    )
  end

  def alert_number # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @alert_number if defined?(@alert_number)
    @alert_number = params[:number].to_i
  end
end
