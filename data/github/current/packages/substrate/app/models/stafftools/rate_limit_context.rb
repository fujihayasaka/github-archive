# typed: true
# frozen_string_literal: true

module Stafftools
  # This class provides the necessary fields for passing into a
  # RateLimitContext.  It is currently being used to facilitate rate limit
  # resets on a particular user.
  class RateLimitContext
    attr_accessor :current_user
    attr_reader :request_owner
    attr_reader :current_app
    attr_reader :current_integration_installation
    attr_reader :authenticated_key

    # These are here to satisfy the context requirements; not to provide
    # actual information.
    attr_accessor :remote_ip

    def initialize(current_user, request_owner: nil, current_app: nil, current_integration_installation: nil)
      @current_user = current_user
      @request_owner = request_owner
      @current_app = current_app
      @current_integration_installation = current_integration_installation
      @authenticated_key = nil
    end
  end
end
