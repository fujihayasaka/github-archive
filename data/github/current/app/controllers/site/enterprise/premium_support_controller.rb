# typed: true
# frozen_string_literal: true

class Site::Enterprise::PremiumSupportController < Site::Enterprise::BaseController
  before_action :allow_initial_cookie_consent
  before_action :enable_microsoft_analytics
  before_action :add_microsoft_analytics_csp_exceptions

  depends_on_clusters ApplicationRecord::Mysql1, only: [:index]

  javascript_bundle "premium-support"
  stylesheet_bundle "premium-support"

  def index
    render "site/enterprise/premium_support/index"
  end
end
