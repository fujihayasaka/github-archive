# typed: true
# frozen_string_literal: true

class Site::Features::CopilotController < Site::Features::BaseController
  extend T::Sig

  before_action :add_csp_exceptions, only: [:index]
  before_action :check_ocid_param, only: [:index]

  sig { returns(String) }
  def self.react_bundle_name
    "landing-pages"
  end

  layout "layouts/site_features"

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
    media_src: [GitHub.asset_host_url],
    frame_src: ["https://www.youtube-nocookie.com"],
  }

  javascript_bundle "marketing-copilot-head"
  stylesheet_bundle "landing-pages"
  stylesheet_bundle "feature-copilot"

  def index
    RevalidatePageJob.perform_later(Site::Contentful::Marketing::LandingPages::Pages::ShowPage, slug: request&.path)
    contentful_page_data = Site::Contentful::Marketing::LandingPages::Pages::ShowPage.new(slug: request&.path).view_data

    utm_params = [:utm_source, :utm_medium, :utm_campaign, :utm_term, :utm_content].freeze
    params = request&.query_parameters.slice(*utm_params)
    copilot_signup_path = "/github-copilot/signup"
    copilot_for_business_signup_path = "/github-copilot/business_signup"
    copilot_enterprise_signup_path = "/github-copilot/signup/plans?plan=enterprise"
    variant_copilot_signup_path = "/github-copilot/signup"

    if params.present?
      copilot_signup_uri = URI::HTTP.build(path: copilot_signup_path, query: params.to_query)
      copilot_signup_path = "#{copilot_signup_uri.path}?#{copilot_signup_uri.query}"

      variant_copilot_signup_uri = URI::HTTP.build(path: variant_copilot_signup_path, query: params.to_query)
      variant_copilot_signup_path = "#{variant_copilot_signup_uri.path}?#{variant_copilot_signup_uri.query}"

      copilot_for_business_signup_uri = URI::HTTP.build(path: copilot_for_business_signup_path, query: params.to_query)
      copilot_for_business_signup_path = "#{copilot_for_business_signup_uri.path}?#{copilot_for_business_signup_uri.query}"
    end

    unless logged_in?
      copilot_signup_path = login_path(return_to: copilot_signup_path)
      copilot_for_business_signup_path = login_path(return_to: copilot_for_business_signup_path)
      variant_copilot_signup_path = nux_signup_index_path(return_to: variant_copilot_signup_path)
    end

    if logged_in? && current_user&.organizations&.any?
      copilot_hero_signup_path = copilot_settings_path
    else
      copilot_hero_signup_path = copilot_signup_path
    end

    copilot_contact_sales_path = enterprise_contact_requests_path(
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
      custom_tags: ["controller:#{controller_path}", "action:#{action_name}"],
      payload: {
        experimentation_copilot_alt_ctas_enabled: GitHub.flipper[:ab_test_feature_copilot_page_alt_ctas].enabled?,
        is_paid_media_campaign: @is_paid_media_ocid,
        has_copilot_subscription: has_copilot_subscription?,
        logged_in: logged_in?,
        contentfulRawJsonResponse: contentful_page_data[:contentful_raw_json_response],
        copilotSignupPath: copilot_signup_path,
        variantCopilotSignupPath: variant_copilot_signup_path,
        copilotForBusinessSignupPath: copilot_for_business_signup_path,
        copilotEnterpriseSignupPath: copilot_enterprise_signup_path,
        copilotContactSalesPath: copilot_contact_sales_path,
        heroVideoLg: static_asset_path("/images/modules/site/copilot/hero-lg.mp4"),
        heroVideoLgPoster: static_asset_path("/images/modules/site/copilot/hero-poster.webp"),
        heroVideoSm: static_asset_path("/images/modules/site/copilot/hero-sm.mp4"),
      },
      ssr: true
    )
  end

  private

  def check_ocid_param
    @is_paid_media_ocid = params[:ocid] == "AIDcmmb150vbv1"
  end

  def has_copilot_subscription?
    return false unless logged_in?

    current_user = T.must(self.current_user)
    copilot_user = Copilot::User.new(current_user)
    copilot_user.has_active_subscription? || copilot_user.has_trial_organization?
  end
end
