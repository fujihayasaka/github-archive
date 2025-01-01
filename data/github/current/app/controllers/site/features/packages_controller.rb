# typed: true
# frozen_string_literal: true

class Site::Features::PackagesController < Site::Features::BaseController
  before_action :add_csp_exceptions, only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1, only: [:index]

  javascript_bundle "marketing-packages"
  stylesheet_bundle "feature-packages"

  CSP_EXCEPTIONS = {
    media_src: [GitHub.asset_host_url]
  }

  def index
    if feature_enabled_globally_or_for_current_user?(:site_fp24)
      redirect_to "/features/actions"
    else
      render "site/features/packages/index"
    end
  end
end
