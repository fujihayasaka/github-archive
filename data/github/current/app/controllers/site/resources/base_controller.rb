# typed: true
# frozen_string_literal: true

class Site::Resources::BaseController < Site::BaseController
  include GitHub::Memoizer
  before_action :add_csp_exceptions

  before_action :enable_fullstory
  before_action :add_fullstory_csp_exceptions

  # Enabling 1DS
  before_action :allow_initial_cookie_consent
  before_action :enable_microsoft_analytics
  before_action :add_microsoft_analytics_csp_exceptions

  private

  memoize def marketing_targeted_countries
    ::TradeControls::Countries.marketing_targeted_countries.map { |name, alpha, *_| { name: name, alpha: alpha } }
  end
end
