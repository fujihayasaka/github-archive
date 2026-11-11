# typed: true
# frozen_string_literal: true

module OSSLicenseCompliance
  module Twirp
    autoload :OSSLicenseComplianceClient, "oss_license_compliance/twirp/oss_license_compliance_client"
    autoload :OSSLicenseComplianceConnection, "oss_license_compliance/twirp/oss_license_compliance_connection"

    class BaseError < StandardError
      attr_accessor :msg
      attr_accessor :twirp_error
    end

    class Error < BaseError; end
    class NonRetryableError < StandardError; end # for errors that should not be retried

    # Twirp errors
    class InternalError < BaseError; end # twirp.code: internal
    class InvalidArgumentError < BaseError; end # twirp.code: invalid_argument
    class InvalidConfigurationError < BaseError; end # twirp.code: failed_precondition for config issues
    class PreconditionFailedError < BaseError; end # twirp.code: failed_precondition
    class ServiceUnavailableError < BaseError; end # twirp.code: unavailable

    # custom errors
    class InvalidSPDXExpressionError < BaseError; end
    class InvalidSPDXIdentifiersError < BaseError; end
  end
end
