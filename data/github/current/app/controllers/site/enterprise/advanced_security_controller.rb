# typed: true
# frozen_string_literal: true

class Site::Enterprise::AdvancedSecurityController < Site::Enterprise::BaseController
  extend T::Sig

  include ReactHelper

  sig { returns(String) }
  def self.react_bundle_name
    "landing-pages"
  end

  depends_on_clusters ApplicationRecord::Mysql1, only: [:index]

  stylesheet_bundle "landing-pages", only: [:index]
  stylesheet_bundle "enterprise-advanced-security", only: [:index]
  javascript_bundle "marketing-security-hero"

  def index
    RevalidatePageJob.perform_later(Site::Contentful::Marketing::LandingPages::Pages::ShowPage, slug: request&.path)
    contentful_page_data = Site::Contentful::Marketing::LandingPages::Pages::ShowPage.new(slug: request&.path).view_data

    request_demo_path = "https://resources.github.com/demo/advanced-security/"

    hero_contact_sales_path = enterprise_contact_requests_path(
      ref_page: T.must(request).fullpath,
      ref_cta: "Contact sales",
      ref_loc: "hero",
      utm_source: "github",
      utm_medium: "site",
      utm_campaign: "adv-security",
      utm_content: "Security",
      scid: ""
    )

    nav_contact_sales_path = enterprise_contact_requests_path(
      ref_page: T.must(request).fullpath,
      ref_cta: "Contact sales",
      ref_loc: "navigation",
      utm_source: "github",
      utm_medium: "site",
      utm_campaign: "adv-security",
      utm_content: "Security",
      scid: ""
    )

    pricing_contact_sales_path = enterprise_contact_requests_path(
      ref_page: T.must(request).fullpath,
      ref_cta: "Contact sales",
      ref_loc: "pricing",
      utm_source: "github",
      utm_medium: "site",
      utm_campaign: "adv-security",
      utm_content: "Security",
      scid: ""
    )

    render_react_app(
      title: "GitHub · Enterprise Application Security · GitHub",
      page_data: {
        description: "Discover application security testing features from GitHub like code scanning, secret scanning, and automated dependency insights for vulnerability detection.",
        class: "header-overlay",
        marketing_page_theme: "dark",
        richweb: {
          title: "GitHub · Enterprise Application Security · GitHub",
          description: "Discover application security testing features from GitHub like code scanning, secret scanning, and automated dependency insights for vulnerability detection.",
          url: T.must(request).original_url,
          image: image_path("modules/site/social-cards/enterprise-advanced-security.jpg"),
        },
      },
      payload: {
        contentfulRawJsonResponse: contentful_page_data[:contentful_raw_json_response],
        requestDemoPath: request_demo_path,
        heroContactSalesPath: hero_contact_sales_path,
        navContactSalesPath: nav_contact_sales_path,
        pricingContactSalesPath: pricing_contact_sales_path,
      },
      ssr: true
    )
  end
end
