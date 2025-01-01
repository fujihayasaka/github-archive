# typed: true
# frozen_string_literal: true

class Site::Features::Copilot::PlansController < Site::Features::BaseController
  extend T::Sig

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

  def index
    utm_params = [:utm_source, :utm_medium, :utm_campaign, :utm_term, :utm_content].freeze
    params = request&.query_parameters.slice(*utm_params)
    copilot_signup_path = "/github-copilot/signup"
    copilot_for_business_signup_path = "/github-copilot/business_signup"
    copilot_enterprise_signup_path = "/github-copilot/signup/plans?plan=enterprise"

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
      payload: {
        copilotSignupPath: copilot_signup_path,
        copilotForBusinessSignupPath: copilot_for_business_signup_path,
        copilotContactSalesPath: copilot_contact_sales_path,
        copilotEnterpriseSignupPath: copilot_enterprise_signup_path,
      },
      ssr: true
    )
  end
end
