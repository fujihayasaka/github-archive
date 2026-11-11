# typed: true
# frozen_string_literal: true

class Site::Features::Copilot::PlansController < Site::Features::BaseController
  before_action :add_csp_exceptions, only: [:index]
  around_action :switch_locale, only: :index

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
    img_src: [GitHub.contentful_marketing_image_host_url],
    media_src: [GitHub.asset_host_url, GitHub.contentful_marketing_asset_host_url],
  }

  stylesheet_bundle "landing-pages"
  stylesheet_bundle "feature-copilot"
  stylesheet_bundle "feature-shared-fp24"

  def index
    contentful_page_data = fetch_contentful_page_data

    return render_404 if contentful_page_data.blank? || landing_page_hidden?(contentful_page_data)

    render_react_landing_page(
      page_data: contentful_page_data,
      page_data_overrides: {
        class: "header-overlay",
      },
      payload: {
        logged_in: logged_in?,
        cft: cohort_funnel_tracking("copilot", "copilot_plans"),
      }.merge(copilot_signup_links),
    )
  end

  private

  def copilot_signup_links
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

    {
      copilotBusinessContactSalesPath: copilot_business_contact_sales_path,
      copilotBusinessSignupPath: "/github-copilot/purchase?priority=business",
      copilotEnterpriseContactSalesPath: copilot_enterprise_contact_sales_path,
      copilotEnterpriseSignupPath: "/github-copilot/purchase?priority=enterprise",
      copilotProPlusSignupPath: copilot_pro_plus_signup_path,
      copilotProSignupPath: copilot_pro_signup_path,
    }
  end

  def cohort_funnel_tracking(funnel, entry_point)
    return params[:ctf] if params[:ctf].present?

    cohort_funnel = funnel
    cohort_funnel += logged_in? ? "_li" : "_lo"

    "#{cohort_funnel}.#{entry_point}"
  end
end
