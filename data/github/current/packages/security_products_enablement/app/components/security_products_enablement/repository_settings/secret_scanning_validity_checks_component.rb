# typed: strict
# frozen_string_literal: true

module SecurityProductsEnablement::RepositorySettings
  class SecretScanningValidityChecksComponent < ServiceComponent # rubocop:disable ViewComponent/ComponentsHaveUnitTests
    delegate :owner, to: :repository

    sig { returns(T::Boolean) }
    def restricted?
      restricted_by_enterprise_policy? || restricted_by_security_configuration?
    end

    sig { override.returns(T::Boolean) }
    def restricted_by_enterprise_policy?
      # This checks `SecurityProduct::AdvancedSecurity` can_enable?/can_disable?
      # which will take the actor into account and allow bypasses if applicable:
      !!data.secret_scanning_validity_checks_blocked_by_policy
    end

    sig { returns(T::Boolean) }
    def is_currently_enabled?
      data.secret_scanning_validity_checks_enabled
    end

    sig { returns(T::Boolean) }
    def ghas_purchased
      repository.owner&.advanced_security_purchased?
    end

    sig { override.returns(T::Boolean) }
    def restricted_by_security_configuration?
      return false unless has_enforced_security_configuration?

      repository.security_configuration!.secret_scanning_validity_checks != "not_set"
    end

    sig { returns(T::Boolean) }
    def display_shield_icon?
      return false if has_mixed_restrictions?

      restricted_by_enterprise_policy? || restricted_by_security_configuration?
    end
  end
end
