# typed: true
# frozen_string_literal: true

module Settings
  module SecurityProducts
    module BlockedSettingsHelper
      extend T::Sig

      # Returns an array of symbols, each one mapping to a GHAS feature.
      # The symbols represent the update_type that will be incremented/decremented in the repo_counter of BlockedSettings
      # within the ApplySecurityConfigurationToRepositoryJob
      sig { params(security_configuration: T.nilable(SecurityConfiguration)).returns(T::Array[Symbol]) }
      def update_types(security_configuration)
        return [] unless security_configuration

        update_types = [T.must(security_configuration).enable_ghas ? :advanced_security_enable_all : :advanced_security_disable_all]
        update_types + [
          [:code_scanning, :auto_codeql_enable_all, :auto_codeql_disable_all],
          [:secret_scanning, :secret_scanning_enable_all, :secret_scanning_disable_all],
          [:secret_scanning_validity_checks, :secret_scanning_validity_checks_enable_all, :secret_scanning_validity_checks_disable_all],
          [:secret_scanning_push_protection, :secret_scanning_push_protection_enable_all, :secret_scanning_push_protection_disable_all]
        ].map do |feature, enable_type, disable_type|
          security_configuration.send("#{feature}_enabled?") ? enable_type : disable_type
        end
      end
    end
  end
end
