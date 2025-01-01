# typed: true
# frozen_string_literal: true

class Site::Features::CopilotController < Site::Features::BaseController
  before_action :add_csp_exceptions, only: [:index]
  before_action :localized_alternative_links, only: :index
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
    frame_src: ["https://www.youtube-nocookie.com"],
    img_src: [GitHub.contentful_marketing_image_host_url],
    media_src: [GitHub.asset_host_url, GitHub.contentful_marketing_asset_host_url, GitHub.contentful_marketing_video_host_url],
  }

  stylesheet_bundle "landing-pages"
  stylesheet_bundle "feature-copilot"

  def index
    options = {
      slug: request&.path,
      preview: fetch_contentful_preview?
    }
    options[:locale] = I18n.locale if user_defined_locale_enabled?

    RevalidatePageJob.perform_later(Site::Contentful::Marketing::LandingPages::Pages::ShowPage, **options) unless fetch_contentful_preview?
    contentful_page_data = Site::Contentful::Marketing::LandingPages::Pages::ShowPage.new(**options).view_data

    return render_404 if contentful_page_data.blank?

    render_react_app(
      app_name: "landing-pages",
      title: contentful_page_data[:title],
      page_data: {
        class: "header-overlay",
        marketing_page_theme: "dark",
        description: contentful_page_data[:seo].try(:dig, :description),
        richweb: {
          description: contentful_page_data[:seo].try(:dig, :description),
          image: contentful_page_data[:seo].try(:dig, :social_media_image),
          title: contentful_page_data[:title],
          url: T.must(request).original_url
        },
        revenue_play: contentful_page_data.fetch(:revenue_play, "AI"),
      },
      custom_tags: ["controller:#{controller_path}", "action:#{action_name}"],
      payload: {
        logged_in: logged_in?,
        contentfulRawJsonResponse: contentful_page_data[:contentful_raw_json_response],
        cft: cohort_funnel_tracking("copilot", "features_copilot"),
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
