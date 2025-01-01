# typed: true
# frozen_string_literal: true

class Site::SolutionsCiCdController < Site::BaseController
  before_action :allow_initial_cookie_consent
  before_action :enable_microsoft_analytics
  before_action :add_microsoft_analytics_csp_exceptions
  before_action :enable_fullstory
  before_action :add_fullstory_csp_exceptions

  depends_on_clusters ApplicationRecord::Mysql1

  def index # rubocop:todo GitHub/UseRestfulActions
    render "site/solutions/ci_cd/index"
  end
end
