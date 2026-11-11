# typed: true
# frozen_string_literal: true

# Protects fetch requests against CSRF attacks without the need for authenticity
# tokens. Same-origin policy dictates that custom headers can not be sent on
# cross-origin requests, except where allowed by CORS.
#
# In addition, the `fetch` standard
# (https://fetch.spec.whatwg.org/#origin-header) dictates that an "origin"
# header (which is considered secure and only set by browsers) must be sent on
# all fetch requests whose method is neither `GET` nor `HEAD`.`
#
# DO NOT return the custom header name in Access-Control-Allow-Headers under any
# circumstances.
#
# See: https://cheatsheetseries.owasp.org/cheatsheets/Cross-Site_Request_Forgery_Prevention_Cheat_Sheet.html#use-of-custom-request-headers
#
# When paired with SameSite cookies, this method provides adequate protection
# against CSRF attacks.
#
# NOTE: If you want to apply this to all methods on a controller, it's simpler
# to include ApplicationController::VerifiedFetchDependency in your controller,
# instead.
#
# This helper is tested in test/integration/application_controller/verified_fetch_dependency_test.rb.
#
# Example:
#
#     class WidgetsController < ApplicationController
#       include ApplicationController::VerifiedFetchDependency
#
#       allow_verified_fetch only: [:create]
#     end
#
#     fetch('/widgets', {
#       method: 'POST',
#       headers: {
#         'GitHub-Verified-Fetch': 'true'
#       }
#     })
module ApplicationController::VerifiedFetchDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  HEADER_NAME = "HTTP_GITHUB_VERIFIED_FETCH"
  HEADER_VALUE = "true"
  STAT_KEY = "verified_fetch"

  included do
    T.bind(self, Class)
    class_attribute :verified_fetch_opts
  end

  module ClassMethods
    extend T::Helpers
    requires_ancestor { ActionController::RequestForgeryProtection::ClassMethods }

    def allow_verified_fetch(opts = {})
      opts[:only] = opts[:only].map(&:to_sym) if opts[:only]
      T.unsafe(self).verified_fetch_opts = opts
      # verify_authenticity_token verfies the request and was previously aliased for clarity.
      # This alias is no longer needed and is removed to avoid confusion.
      protect_from_forgery with: ForgeryProtectionStrategies::AllowVerifiedFetch, if: :verify_authenticity_token?
    end
  end

  mixes_in_class_methods(ClassMethods)
  requires_ancestor { ApplicationController }

  def use_verified_fetch?
    only = T.unsafe(self.class).verified_fetch_opts[:only]

    return false if only&.exclude?(action_name.to_sym)

    verified_fetch_header.present?
  end

  def verify_fetch
    # Verify the custom header is present and its value is what we expect.
    if verified_fetch_header != ApplicationController::VerifiedFetchDependency::HEADER_VALUE
      ApplicationController::VerifiedFetchDependency.increment_stat(false, reason: "invalid_header_value", logged_in: logged_in?)
      return ApplicationController::VerifiedFetchDependency.fallback(self)
    end

    # For verified fetch requests, we require an "Origin" header.
    # https://github.com/github/github/pull/217797#discussion_r858978187
    if request.origin.blank? || request.origin != request.base_url
      ApplicationController::VerifiedFetchDependency.increment_stat(false, reason: "invalid_origin", logged_in: logged_in?)
      return ApplicationController::VerifiedFetchDependency.fallback(self)
    end

    ApplicationController::VerifiedFetchDependency.increment_stat(true, logged_in: logged_in?)
  end

  def verify_fetch_fallback
    ApplicationController::VerifiedFetchDependency.fallback(self)
  end

  def self.increment_stat(valid, reason: nil, logged_in:)
    tags = ["valid:#{valid}", "logged_in:#{logged_in}"]
    tags << "reason:#{reason}" unless reason.nil?
    GitHub.dogstats.increment(STAT_KEY, tags: tags)
  end

  def self.fallback(controller)
    ActionController::RequestForgeryProtection::ProtectionMethods::Exception.new(controller).handle_unverified_request
  end

  private

  def verified_fetch_header
    request.env[ApplicationController::VerifiedFetchDependency::HEADER_NAME]
  end
end
