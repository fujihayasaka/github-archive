# typed: strict
# frozen_string_literal: true

# Code for Request-HMAC verification.
# Include this in a controller and use #require_request_hmac in a before_action
# to enforce hmac authentication for endpoints.
# The Request-HMAC header can be sent by
# internal services with API requests to identify themselves as trusted.
module OctoCore::Api::HmacFilter
  extend T::Helpers
  extend T::Sig

  include OctoCore::Api::ErrorHandling

  requires_ancestor { ActionController::Metal }

  REQUEST_HMAC_HEADER = "HTTP_REQUEST_HMAC"
  REQUEST_HMAC_INVALID = "Request-HMAC is not valid."

  sig { void }
  def require_request_hmac
    unless hmac_authenticated_internal_service_request?
      deliver_error(403, message: REQUEST_HMAC_INVALID)
    end
  end

  sig { overridable.returns(T.nilable(T::Array[String])) }
  def hmac_keys_override; nil; end

  private

  sig { returns(T.nilable(T::Array[String])) }
  def valid_hmac_keys
    return @valid_hmac_keys if defined?(@valid_hmac_keys)

    @valid_hmac_keys = T.let(
      hmac_keys_override || OctoCore::Auth::Hmac.internal_api_hmac_keys,
      T.nilable(T::Array[String])
    )
  end

  sig { params(received_hmac: String).returns([Symbol, T.nilable(String)]) }
  def verify_hmac(received_hmac)
    OctoCore::Auth::Hmac.verify_hmac(received_hmac, valid_hmac_keys)
  end

  sig { returns(T::Boolean) }
  def hmac_authenticated_internal_service_request?
    received_hmac = request.headers[REQUEST_HMAC_HEADER]
    return false unless received_hmac.present?
    hmac_status, _matching_key = verify_hmac(received_hmac)
    hmac_status == :success
  end
end
