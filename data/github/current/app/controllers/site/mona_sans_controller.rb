# typed: true
# frozen_string_literal: true

class Site::MonaSansController < Site::BaseController
  before_action :add_csp_exceptions, only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1, only: [:index]

  CSP_EXCEPTIONS = {
    media_src: [GitHub.asset_host_url]
  }

  javascript_bundle "mona-sans"
  stylesheet_bundle "mona-sans"

  def index
    render "site/mona_sans/index"
  end
end
