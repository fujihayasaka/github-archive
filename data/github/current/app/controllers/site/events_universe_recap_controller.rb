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
    contentful_page_data = fetch_contentful_page_data

    return render_404 if contentful_page_data.blank? || landing_page_hidden?(contentful_page_data)

    render_react_landing_page(
      page_data: contentful_page_data,
      page_data_overrides: {
        class: "header-white",
      },
    )
  end
end
