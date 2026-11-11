# typed: true
# frozen_string_literal: true

class Site::SitemapController < Site::BaseController
  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:index]

  def index
    render "site/sitemap/index"
  end
end
