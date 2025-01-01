# typed: true
# frozen_string_literal: true

module OSSLicenseCompliance
  module Twirp
    autoload :OSSLicenseComplianceConnection, "oss_license_compliance/twirp/oss_license_compliance_connection"
    autoload :OSSLicenseComplianceClient, "oss_license_compliance/twirp/oss_license_compliance_client"

    class NonRetryableError < StandardError; end
    class BaseError < StandardError; attr_accessor :msg; end
    class Error < BaseError; end
    class ServiceUnavailableError < BaseError; end
    class InvalidConfigurationError < BaseError; end
  end
end
