# typed: true
# frozen_string_literal: true

class Site::Features::IntegrationsController < Site::BaseController
  before_action :add_csp_exceptions, only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1, only: [:index]

  CSP_EXCEPTIONS = {
    frame_src: ["https://www.youtube.com"],
  }

  stylesheet_bundle "site-legacy"

  def index
    render "site/features/integrations/index"
  end
end
