# typed: true
# frozen_string_literal: true
class Hovercards::DependabotAlertsController < AbstractRepositoryController
  include Hovercards::ConditionalAccessMethods

  before_action :require_xhr
  before_action :require_access_to_dependabot_alerts

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Notify,
    only: [:show]

  def show
    alert = current_repository.repository_vulnerability_alerts.find_by_number(params.require(:number))

    return render_404 unless alert

    render "hovercards/dependabot_alerts/show",
      locals: {
        repository: current_repository,
        alert: alert,
        state_properties: state_component_properties(alert.state),
      },
      layout: false
  end

  private

  def target_type # rubocop:todo GitHub/UseRestfulActions
    # Needed by Hovercards::ConditionalAccessMethods to display in the error message when hovercard is being viewed from a non-allowed IP address.
    "dependabot alert"
  end

  def require_access_to_dependabot_alerts
    render_404 unless current_repository&.vulnerability_alerts_visible_to?(current_user)
  end

  def state_component_properties(state)
    default_properties = { scheme: :default, icon: "shield" }
    case state.to_sym
    when :dismissed
      default_properties.merge({
        title: "Status: Dismissed",
        label: "Dismissed",
        scheme: :closed,
        icon: "shield-slash"
      })
    when :fixed
      default_properties.merge({
        title: "Status: Fixed",
        label: "Fixed",
        scheme: :merged,
        icon: "shield-check"
      })
    when :open
      default_properties.merge({
        title: "Status: Open",
        label: "Open",
        scheme: :open
      })
    when :auto_dismissed
      default_properties.merge({
        title: "Status: Auto-dismissed",
        label: "Dismissed",
        scheme: :closed,
        icon: "shield-slash"
      })
    end
  end
end
