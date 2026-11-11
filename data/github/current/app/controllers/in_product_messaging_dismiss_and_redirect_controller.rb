# typed: true
# frozen_string_literal: true

class InProductMessagingDismissAndRedirectController < ApplicationController
  depends_on_clusters ApplicationRecord::Domain::Users,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities

  before_action :login_required

  DESTINATION_PATHS = {
    "nudge_organization_win_cb_users_back_credit_offer_to_accept" => "/settings/organizations?cb_200_offer_notice=1",
    "org_overview_roadmap_webinar_2025_q4_nudge_amer_emea" => "https://github.com/resources/events/github-roadmap-webinar-q4?utm_source=github&utm_medium=in_product_message&utm_campaign=AMER-FY26Q2-AMER_EMEA-WBRL-Roadmap-in_product_message-20251113&utm_content=in_product_message",
    "org_overview_roadmap_webinar_2025_q4_nudge_apac" => "https://github.com/resources/events/github-roadmap-webinar-q4-apac?utm_source=github&utm_medium=in_product_message&utm_campaign=APAC-FY26Q2-APAC-WBRL-Roadmap-in_product_message-20251125&utm_content=in_product_message",
    "dashboard_onboarding_copilot_free" => "https://github.com/copilot?utm_source=github&utm_medium=banner&utm_campaign=copilotfree-bannerdashboard-onboarding",
    "github_universe_2025_dashboard_nudge" => "https://githubuniverse.com#signup",
    "org_overview_roadmap_webinar_2025_q3_nudge_pre_event" => "https://resources.github.com/webcasts/github-roadmap-webinar-q3-americas-europe?utm_source=github&utm_medium=in_product_message&utm_campaign=AMER-FY26Q1-AMER-WBRL-Roadmap-Webinar-AMER_EMEA-20250821",
    "dashboard_spark_public_preview_nudge" => "https://github.com/spark",
    "site_universe_25_banners_day_1_pre_event" => "https://githubuniverse.com/?utm_source=Banner&utm_medium=GitHub&utm_campaign=keyn_countdown",
    "site_universe_25_banners_day_1_during_event" => "https://githubuniverse.com/?utm_source=Banner&utm_medium=GitHub&utm_campaign=key25",
    "site_universe_25_banners_day_1_post_event" => "https://github.com/events/universe/recap?utm_source=Banner&utm_medium=GitHub&utm_campaign=day_1_post_event",
    "site_universe_25_banners_day_2_pre_event" => "https://githubuniverse.com/?utm_source=Banner&utm_medium=GitHub&utm_campaign=key_2_count",
    "site_universe_25_banners_day_2_during_event" => "https://githubuniverse.com/?utm_source=Banner&utm_medium=GitHub&utm_campaign=key_2",
    "site_universe_25_banners_day_2_post_event" => "https://github.com/events/universe/recap?utm_source=Banner&utm_medium=GitHub&utm_campaign=day_2_post_event"
  }.freeze

  # GET /in-product-messaging/dismiss-and-redirect
  # Dismisses a notice and redirects to destination URL based on key lookup
  def show
    notice = params[:notice]
    destination_key = params[:destination_key]
    group = params[:group].present? ? params[:group].to_sym : nil
    business_id = params[:business_id].presence&.to_i
    organization_id = params[:organization_id].presence&.to_i

    if notice.present?
      # Use connected write role to avoid replication lag
      ActiveRecord::Base.connected_to(role: :writing) do
        current_user.track_nudge_click(id: notice, group: group, org_id: organization_id, enterprise_id: business_id)

        if business_id
          current_user.dismiss_business_notice(
            notice,
            business_id: business_id,
          )
          current_user.track_nudge_dismissal(id: notice, group: group, enterprise_id: business_id)
        elsif organization_id && (organization = Organization.find_by(id: organization_id))
          current_user.dismiss_organization_notice(notice, organization)
          current_user.track_nudge_dismissal(id: notice, group: group, org_id: organization_id)
        else
          current_user.dismiss_notice(notice)
          current_user.track_nudge_dismissal(id: notice, group: group)
        end
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
