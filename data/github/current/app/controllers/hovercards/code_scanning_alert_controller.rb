# typed: true
# frozen_string_literal: true

class Hovercards::CodeScanningAlertController < AbstractRepositoryController
  include Hovercards::ConditionalAccessMethods

  before_action :require_alerts_viewable
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
    only: [:hovercard]

  def hovercard # rubocop:todo GitHub/UseRestfulActions
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
        title: alert.rule&.short_description.present? ? alert.rule&.short_description : helpers.result_message_text(alert),
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

  def require_alerts_viewable
    render_404 unless (
      alert_number.present? && alert_number > 0 &&
      current_repository&.code_scanning_enabled? &&
      current_repository&.code_scanning_readable_by?(current_user)
    )
  end

  def alert_number # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @alert_number if defined?(@alert_number)
    @alert_number = params[:number].to_i
  end
end
