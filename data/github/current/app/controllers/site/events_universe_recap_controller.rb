# typed: true
# frozen_string_literal: true

class Site::EventsUniverseRecapController < Site::BaseController
  before_action :add_csp_exceptions, only: [:index]
  before_action :localized_alternative_links, only: :index
  around_action :switch_locale, only: :index

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Copilot,
    ApplicationRecord::IamAbilities,
    only: [:index]

  CSP_EXCEPTIONS = {
    frame_src: ["https://www.youtube-nocookie.com"],
    img_src: [GitHub.asset_host_url, GitHub.og_image_generator_base_url, GitHub.contentful_marketing_image_host_url],
    media_src: [GitHub.asset_host_url, GitHub.contentful_marketing_asset_host_url, GitHub.contentful_marketing_video_host_url],
  }

  stylesheet_bundle :"landing-pages", only: [:index]
  javascript_bundle :"marketing-essentials", only: [:index]

  def index
    options = {
      slug: request&.path,
      preview: fetch_contentful_preview?
    }
    options[:locale] = I18n.locale if user_defined_locale_enabled?

    RevalidatePageJob.perform_later(Site::Contentful::Marketing::LandingPages::Pages::ShowPage, **options) unless fetch_contentful_preview?
    contentful_page_data = Site::Contentful::Marketing::LandingPages::Pages::ShowPage.new(**options).view_data

    render_404 and return if contentful_page_data.blank? || hidden?(contentful_page_data)

    render_react_app(
      app_name: "landing-pages",
      title: contentful_page_data[:title],
      page_data: {
        class: "header-white",
        marketing_page_theme: "light",
        description: contentful_page_data[:seo].try(:dig, :description),
        richweb: {
          description: contentful_page_data[:seo].try(:dig, :description),
          image: contentful_page_data[:seo].try(:dig, :social_media_image),
          title: contentful_page_data[:title],
          url: T.must(request).original_url
        },
        revenue_play: contentful_page_data.fetch(:revenue_play, ""),
      },
      payload: {
        contentfulRawJsonResponse: contentful_page_data[:contentful_raw_json_response],
      },
    )
  end

  private

  def hidden?(show_page_data)
    feature_flag = show_page_data.fetch(:feature_flag, nil)

    return false if feature_flag.nil?

    !FeatureFlag.vexi.enabled?(feature_flag, current_user, default: false)
  end
end
