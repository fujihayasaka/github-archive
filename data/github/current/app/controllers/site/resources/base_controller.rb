# typed: true
# frozen_string_literal: true

class Site::Resources::BaseController < Site::BaseController
  before_action :add_csp_exceptions

  before_action :enable_fullstory
  before_action :add_fullstory_csp_exceptions

  # Enabling 1DS
  before_action :allow_initial_cookie_consent
  before_action :enable_microsoft_analytics
  before_action :add_microsoft_analytics_csp_exceptions
end
