# typed: true
# frozen_string_literal: true

class DismissalsController < ApplicationController
  before_action :login_required

  DESTINATION_PATHS = {
    "dashboard_2025_03_27_roadmap_post_event" => "https://resources.github.com/webcasts/github-roadmap-webinar-q1-americas?utm_source=github&utm_medium=banner&utm_campaign=2025q3-wbr-amer-GitHub_Public_Roadmap-AMER&utm_content=inproduct_post",
    "dashboard_2025_03_27_roadmap_pre_event_a" => "https://resources.github.com/webcasts/github-roadmap-webinar-q1-americas?utm_source=github&utm_medium=bannerA&utm_campaign=2025q3-wbr-amer-GitHub_Public_Roadmap-AMER&utm_content=inproduct",
    "dashboard_2025_03_27_roadmap_pre_event_b" => "https://resources.github.com/webcasts/github-roadmap-webinar-q1-americas?utm_source=github&utm_medium=bannerB&utm_campaign=2025q3-wbr-amer-GitHub_Public_Roadmap-AMER&utm_content=inproduct",
    "dashboard_2025_03_27_roadmap_pre_event_emea" => "https://resources.github.com/webcasts/github-roadmap-webinar-q1-europe-middle-east-africa/?utm_source=github&utm_medium=inproductbanner&utm_campaign=2025q3-wbr-emea-GitHub_Public_Roadmap-EMEA",
  }.freeze

  # GET /click-and-dismiss
  # Dismisses a notice and redirects to destination URL based on key lookup
  def show
    notice = params[:notice]
    destination_key = params[:destination_key]

    if notice.present?
      # Use connected write role to avoid replication lag
      ActiveRecord::Base.connected_to(role: :writing) do
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
