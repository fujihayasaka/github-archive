# typed: true
# frozen_string_literal: true

class Site::LogosController < Site::BaseController
  depends_on_clusters ApplicationRecord::Mysql1, only: [:index]

  def index
    render "site/logos/index"
  end
end
