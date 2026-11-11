# typed: true
# frozen_string_literal: true

class Site::Features::Copilot::AiCodeEditorController < Site::Features::BaseController
  before_action :add_csp_exceptions, only: [:index]
  around_action :switch_locale, only: :index

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    only: [:index]

  CSP_EXCEPTIONS = {
    frame_src: ["https://www.youtube-nocookie.com"],
    img_src: [GitHub.contentful_marketing_image_host_url],
    media_src: [GitHub.asset_host_url, GitHub.contentful_marketing_asset_host_url, GitHub.contentful_marketing_video_host_url],
  }.freeze

  before_action :load_landing_pages_stylesheet
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
      payload: {
        contentfulRawJsonResponse: contentful_page_data[:contentful_raw_json_response],
      }
    )
  end
end
