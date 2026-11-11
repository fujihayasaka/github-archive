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
    contentful_page_data = fetch_contentful_page_data

    return render_404 if contentful_page_data.blank? || landing_page_hidden?(contentful_page_data)

    copilot_user = logged_in? ? Copilot::User.new(T.must(current_user)) : nil

    render_react_landing_page(
      page_data: contentful_page_data,
      page_data_overrides: {
        class: "header-overlay",
      },
      payload: {
        hasCopilot: copilot_user&.has_copilot_access? || false,
        hasCopilotPaid: copilot_user&.has_paid_access? || false,
        hasCopilotPro: copilot_user&.has_pro_access? || false,
      },
    )
  end
end
