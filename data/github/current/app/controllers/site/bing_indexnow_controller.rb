# typed: true
# frozen_string_literal: true

class Site::BingIndexnowController < Site::BaseController
  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:index]
  before_action :set_header_for_no_index_and_no_follow
  before_action :disable_in_enterprise_and_proxima

  def index
    render plain: GitHub.bing_indexnow_api_key
  end
end
