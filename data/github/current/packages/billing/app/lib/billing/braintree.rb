# typed: true
# frozen_string_literal: true

module Billing
  module Braintree
    RETRYABLE_ERRORS = [
      ::Braintree::ServiceUnavailableError,
      ::Braintree::SSLCertificateError,
      ::Braintree::ServerError,
      ::Braintree::GatewayTimeoutError,
      ::Braintree::RequestTimeoutError,
      ::Braintree::TooManyRequestsError,
    ]
  end
end
