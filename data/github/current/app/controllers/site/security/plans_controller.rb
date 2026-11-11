# typed: true
# frozen_string_literal: true

class Site::Security::PlansController < Site::Security::BaseController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
  only: [:index]

  before_action :add_csp_exceptions
  around_action :switch_locale

  CSP_EXCEPTIONS = {
    img_src: [GitHub.contentful_marketing_image_host_url],
  }.freeze

  stylesheet_bundle "landing-pages"

  def index
    contentful_page_data = fetch_contentful_page_data

    return render_404 if contentful_page_data.blank? || landing_page_hidden?(contentful_page_data)

    render_react_landing_page(
      page_data: contentful_page_data,
      page_data_overrides: {
        class: "header-dark",
      },
    )
  end
end
