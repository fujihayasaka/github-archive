# typed: true
# frozen_string_literal: true

class InProductMessagingDismissAndRedirectController < ApplicationController
  depends_on_clusters ApplicationRecord::Domain::Users,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities

  before_action :login_required

  DESTINATION_PATHS = {
    "dashboard_onboarding_copilot_free" => "https://github.com/copilot?utm_source=github&utm_medium=banner&utm_campaign=copilotfree-bannerdashboard-onboarding",
    "github_universe_2025_dashboard_nudge" => "https://githubuniverse.com/#agenda?utm_source=in_product_message&utm_medium=GitHub&utm_campaign=dashboard_3",
    "org_overview_roadmap_webinar_2025_q3_nudge_pre_event" => "https://resources.github.com/webcasts/github-roadmap-webinar-q3-americas-europe?utm_source=github&utm_medium=in_product_message&utm_campaign=AMER-FY26Q1-AMER-WBRL-Roadmap-Webinar-AMER_EMEA-20250821",
    "dashboard_spark_public_preview_nudge" => "https://github.com/spark"
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
