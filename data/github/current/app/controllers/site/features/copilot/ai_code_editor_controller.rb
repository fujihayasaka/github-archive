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

  stylesheet_bundle "landing-pages"
  stylesheet_bundle "feature-copilot"

  def index
    contentful_page_data = fetch_contentful_page_data

    return render_404 if contentful_page_data.blank? || landing_page_hidden?(contentful_page_data)

    render_react_landing_page(
      page_data: contentful_page_data,
      page_data_overrides: {
        class: "header-overlay",
      },
    )
  end
end
