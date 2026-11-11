# typed: true
# frozen_string_literal: true

# Uses fetch verification to protect against CSRF attacks, rather than
# authentication tokens.
#
# See ApplicationController::VerifiedFetchDependency for details and use.
module ForgeryProtectionStrategies
  class AllowVerifiedFetch
    def initialize(controller)
      @controller = controller
    end

    def handle_unverified_request
      if @controller.use_verified_fetch?
        @controller.verify_fetch
      else
        @controller.verify_fetch_fallback
      end
    end
  end
end
