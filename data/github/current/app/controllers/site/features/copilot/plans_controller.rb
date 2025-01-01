# typed: true
# frozen_string_literal: true

class Site::Features::Copilot::PlansController < Site::Features::BaseController

  before_action :add_csp_exceptions, only: [:index]

  include ReactHelper

  sig { returns(String) }
  def self.react_bundle_name
    "landing-pages"
  end

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Copilot,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:index]

  CSP_EXCEPTIONS = {
    media_src: [GitHub.asset_host_url]
  }

  stylesheet_bundle "landing-pages"
  stylesheet_bundle "feature-copilot"
  stylesheet_bundle "feature-shared-fp24"

  def index
    add_client_feature_flag([:digital_front_door_mvp])
    utm_params = [:utm_source, :utm_medium, :utm_campaign, :utm_term, :utm_content].freeze
    params = request&.query_parameters.slice(:cft, *utm_params)
    copilot_signup_path = "/github-copilot/signup"
    copilot_for_business_signup_path = "/github-copilot/business_signup"
    copilot_for_business_signup_path_refresh = "/github-copilot/purchase?priority=business"
    copilot_enterprise_signup_path = "/github-copilot/purchase?priority=enterprise"

    if params.present?
      copilot_signup_uri = URI::HTTP.build(path: copilot_signup_path, query: params.to_query)
      copilot_signup_path = "#{copilot_signup_uri.path}?#{copilot_signup_uri.query}"

      copilot_for_business_signup_uri = URI::HTTP.build(path: copilot_for_business_signup_path, query: params.to_query)
      copilot_for_business_signup_path = "#{copilot_for_business_signup_uri.path}?#{copilot_for_business_signup_uri.query}"
    end

    unless logged_in?
      copilot_signup_path = login_path(return_to: copilot_signup_path)
      copilot_for_business_signup_path = login_path(return_to: copilot_for_business_signup_path)
    end

    if logged_in? && current_user&.organizations&.any?
      copilot_hero_signup_path = copilot_settings_path
    else
      copilot_hero_signup_path = copilot_signup_path
    end

    copilot_contact_sales_path = enterprise_contact_path(
      ref_page: T.must(request).fullpath,
      ref_cta: "Contact sales",
      ref_loc: "pricing",
      utm_source: "github",
      utm_medium: "site",
      utm_campaign: "Copilot_feature_page_contact_sales_cta_utmroutercampaign",
      scid: ""
    )

    render_react_app(
      title: "GitHub Copilot · Your AI pair programmer",
      page_data: {
        class: "header-overlay",
        marketing_page_theme: "dark",
        richweb: {
          title: "GitHub Copilot · Your AI pair programmer",
          description: "GitHub Copilot works alongside you directly in your editor, suggesting whole lines or entire functions for you.",
          url: T.must(request).original_url,
          image: image_path("modules/site/social-cards/copilot-2023.png"),
        },
      },
      payload: {
        siteUniverse24: feature_enabled_globally_or_for_current_user?(:site_universe24_features_copilot),
        siteCopilotPurchaseRefresh: feature_enabled_globally_or_for_current_user?(:copilot_purchase_flow_refresh),
        copilotSignupPath: copilot_signup_path,
        copilotForBusinessSignupPath: copilot_for_business_signup_path,
        copilotForBusinessSignupPathRefresh: copilot_for_business_signup_path_refresh,
        copilotContactSalesPath: copilot_contact_sales_path,
        copilotEnterpriseSignupPath: copilot_enterprise_signup_path,
        cft: cohort_funnel_tracking("copilot", "copilot_plans"),
      },
      ssr: true
    )
  end

  private

  def cohort_funnel_tracking(funnel, entry_point)
    return params[:ctf] if params[:ctf].present?

    cohort_funnel = funnel
    cohort_funnel += logged_in? ? "_li" : "_lo"

    "#{cohort_funnel}.#{entry_point}"
  end
end
