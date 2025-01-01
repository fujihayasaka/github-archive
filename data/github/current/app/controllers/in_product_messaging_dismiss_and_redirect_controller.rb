# typed: true
# frozen_string_literal: true

class InProductMessagingDismissAndRedirectController < ApplicationController
  depends_on_clusters ApplicationRecord::Domain::Users,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Collab

  before_action :login_required

  DESTINATION_PATHS = {
    "dashboard_onboarding_copilot_free"             => "https://github.com/copilot?utm_source=github&utm_medium=banner&utm_campaign=copilotfree-bannerdashboard-onboarding",
    "dashboard_copilot_agent_mode_launch_nudge"     => "https://vscodelauncher.github.com/copilot-agent",
    "dashboard_copilot_agent_mode_launch_nudge_step_2" => "https://github.com/continuous-copilot/build-applications-w-copilot-agent-mode",
    "dashboard_copilot_agent_mode_launch_nudge_step_3" => "https://www.youtube.com/watch?v=aKx5I0Mrr9g",
  }.freeze

  # GET /in-product-messaging/dismiss-and-redirect
  # Dismisses a notice and redirects to destination URL based on key lookup
  def show
    notice = params[:notice]
    destination_key = params[:destination_key]
    group = params[:group].present? ? params[:group].to_sym : nil

    if notice.present?
      # Use connected write role to avoid replication lag
      ActiveRecord::Base.connected_to(role: :writing) do
        current_user.track_nudge_click(id: notice, group: group)
        current_user.dismiss_notice(notice)
      end
    end

    # Redirect to github.com if destination key not found in map
    if destination_key.present? && DESTINATION_PATHS.key?(destination_key)
      redirect_to DESTINATION_PATHS[destination_key]
    else
      redirect_to "https://github.com"
    end
  end

  private

  # Since we're only dismissing notices for the current user, return current_user as the target
  def resource_for_conditional_access
    return :no_target_for_conditional_access unless logged_in?
    return :no_target_for_conditional_access if GitHub::DeniedLogins.include? current_user.display_login.downcase
    current_user
  end

  def target_for_conditional_access
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
