# typed: true
# frozen_string_literal: true

class Site::About::LeadershipController < Site::About::BaseController
  before_action :add_csp_exceptions
  before_action :enable_fullstory
  before_action :add_fullstory_csp_exceptions

  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:index]

  CSP_EXCEPTIONS = {
    img_src: [GitHub.contentful_marketing_image_host_url],
    media_src: [GitHub.contentful_marketing_asset_host_url],
  }

  def index
    page = Site::Contentful::Marketing::Page.find("leadership")

    if page.present?
      render "site/about/leadership/index", locals: { page: page }
    else
      render_404
    end
  end
end
