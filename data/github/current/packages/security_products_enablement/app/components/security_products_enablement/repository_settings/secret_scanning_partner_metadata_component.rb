# typed: strict
# frozen_string_literal: true

module SecurityProductsEnablement::RepositorySettings
  class SecretScanningPartnerMetadataComponent < ApplicationComponent # rubocop:disable ViewComponent/ComponentsHaveUnitTests
    include ServiceComponentMethods

    sig { returns(T::Boolean) }
    def restricted?
      restricted_by_enterprise_policy? || restricted_by_security_configuration?
    end

    sig { returns(T::Boolean) }
    def is_currently_enabled?
      data.secret_scanning_partner_metadata_enabled
    end

    sig { returns(T::Boolean) }
    def blocked_by_in_progress_setting?
      data.secret_scanning_partner_metadata_blocked_by_in_progress_setting
    end

    sig { override.returns(T::Boolean) }
    def restricted_by_enterprise_policy?
      # This checks `SecurityProduct::AdvancedSecurity` can_enable?/can_disable?
      # which will take the actor into account and allow bypasses if applicable:
      !!data.secret_scanning_partner_metadata_blocked_by_policy
    end

    sig { override.returns(T::Boolean) }
    def restricted_by_security_configuration?
      security_configuration = enforced_security_configuration
      return false unless security_configuration

      security_configuration.secret_scanning_extended_metadata != "not_set"
    end

    sig { returns(T::Boolean) }
    def display_shield_icon?
      return false if has_mixed_restrictions?

      restricted_by_enterprise_policy? || restricted_by_security_configuration?
    end
  end
end
