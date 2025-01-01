# typed: true
# frozen_string_literal: true

class Site::Features::Copilot::PlansController < Site::Features::BaseController

  before_action :add_csp_exceptions, only: [:index]


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
    RevalidatePageJob.perform_later(Site::Contentful::Marketing::LandingPages::Pages::ShowPage, slug: request&.path.gsub("/plans", ""))
    contentful_page_data = Site::Contentful::Marketing::LandingPages::Pages::ShowPage.new(slug: request&.path.gsub("/plans", "")).view_data

    utm_params = [:utm_source, :utm_medium, :utm_campaign, :utm_term, :utm_content].freeze
    params = request&.query_parameters.slice(:cft, *utm_params)
    copilot_signup_path = "/github-copilot/signup"
    copilot_for_business_signup_path = "/github-copilot/purchase?priority=business"
    copilot_enterprise_signup_path = "/github-copilot/purchase?priority=enterprise"

    if params.present?
      copilot_signup_uri = URI::HTTP.build(path: copilot_signup_path, query: params.to_query)
      copilot_signup_path = "#{copilot_signup_uri.path}?#{copilot_signup_uri.query}"
    end

    unless logged_in?
      copilot_signup_path = login_path(return_to: copilot_signup_path)
    end

    if logged_in? && current_user&.organizations&.any?
      copilot_hero_signup_path = copilot_settings_path
    else
      copilot_hero_signup_path = copilot_signup_path
    end

    copilot_business_contact_sales_path = enterprise_contact_path(
      ref_page: T.must(request).fullpath,
      ref_cta: "Contact sales",
      ref_loc: "pricing",
      utm_source: "github",
      utm_medium: "site",
      utm_campaign: "Copilot_feature_page_contact_sales_cta_CopilotBusiness_utmroutercampaign",
      scid: ""
    )

    copilot_enterprise_contact_sales_path = enterprise_contact_path(
      ref_page: T.must(request).fullpath,
      ref_cta: "Contact sales",
      ref_loc: "pricing",
      utm_source: "github",
      utm_medium: "site",
      utm_campaign: "Copilot_feature_page_contact_sales_cta_CopilotEnterprise_utmroutercampaign",
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
        revenue_play: "AI",
      },
      payload: {
        has_copilot_subscription: has_copilot_subscription?,
        logged_in: logged_in?,
        userHasOrgs: user_has_orgs?,
        contentfulRawJsonResponse: contentful_page_data[:contentful_raw_json_response],
        copilotProSignupPath: copilot_signup_individual_path,
        copilotForBusinessSignupPath: copilot_for_business_signup_path,
        copilotBusinessContactSalesPath: copilot_business_contact_sales_path,
        copilotEnterpriseContactSalesPath: copilot_enterprise_contact_sales_path,
        copilotEnterpriseSignupPath: copilot_enterprise_signup_path,
        cft: cohort_funnel_tracking("copilot", "copilot_plans"),
      },
    )
  end

  private

  def has_copilot_subscription?
    return false unless logged_in?

    current_user = T.must(self.current_user)
    copilot_user = Copilot::User.new(current_user)

    copilot_user.has_active_subscription? || copilot_user.has_trial_organization? || copilot_user.has_limited_access?
  end

  def user_has_orgs?
    return false unless logged_in?

    current_user = T.must(self.current_user)
    current_user.owned_or_billing_manager_organizations.any?
  end

  def cohort_funnel_tracking(funnel, entry_point)
    return params[:ctf] if params[:ctf].present?

    cohort_funnel = funnel
    cohort_funnel += logged_in? ? "_li" : "_lo"

    "#{cohort_funnel}.#{entry_point}"
  end
end
