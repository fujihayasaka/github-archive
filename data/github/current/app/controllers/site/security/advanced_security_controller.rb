# typed: true
# frozen_string_literal: true

class Site::Security::AdvancedSecurityController < Site::Security::BaseController
  depends_on_clusters ApplicationRecord::Mysql1, only: [:index]

  before_action :add_csp_exceptions
  before_action :localized_alternative_links, only: :index
  around_action :switch_locale, only: :index

  CSP_EXCEPTIONS = {
    img_src: [GitHub.contentful_marketing_image_host_url],
  }.freeze

  stylesheet_bundle "landing-pages", only: [:index]
  stylesheet_bundle "security-advanced-security", only: [:index]

  def index
    options = { slug: request&.path }
    options[:locale] = I18n.locale if feature_enabled_globally_or_for_current_user?(:marketing_localization_experiment)

    RevalidatePageJob.perform_later(Site::Contentful::Marketing::LandingPages::Pages::ShowPage, **options)
    contentful_page_data = Site::Contentful::Marketing::LandingPages::Pages::ShowPage.new(**options).view_data

    title = "GitHub Advanced Security · Built-in protection for every repository"

    render_react_app(
      app_name: "landing-pages",
      title: title,
      page_data: {
        class: "header-overlay",
        marketing_page_theme: "dark",
        richweb: {
          title: title,
          description: "Fix vulnerabilities and safeguard your software supply chain with built-in, AI-powered security.",
          url: T.must(request).original_url,
          image: image_path("modules/site/social-cards/security-advanced-security.jpg"),
        },
        revenue_play: "Security",
      },
      payload: {
        contentfulRawJsonResponse: contentful_page_data[:contentful_raw_json_response],
      }
    )
  end
end
