# typed: true
# frozen_string_literal: true

class Site::TeamController < Site::BaseController
  before_action :allow_initial_cookie_consent
  before_action :enable_microsoft_analytics
  before_action :add_microsoft_analytics_csp_exceptions
  before_action :enable_fullstory
  before_action :add_fullstory_csp_exceptions

  depends_on_clusters ApplicationRecord::Mysql1, only: [:index]

  stylesheet_bundle "team"

  def index
    render "site/team/index"
  end
end
