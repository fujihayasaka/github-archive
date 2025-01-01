# typed: strict
# frozen_string_literal: true

module SecurityProductsEnablement::RepositorySettings
  class SecretScanningDelegatedClosuresComponent < ServiceComponent # rubocop:disable ViewComponent/ComponentsHaveUnitTests

    # This feature is configurable on repository settings and (temporarily) on org global settings, but not (yet)
    # via security configurations.

    sig { returns(T::Boolean) }
    def restricted?
      restricted_by_enterprise_policy? || restricted_by_security_configuration?
    end

    sig { override.returns(T::Boolean) }
    def restricted_by_enterprise_policy?
      false
    end

    sig { returns(T::Boolean) }
    def is_currently_enabled?
      data.secret_scanning_delegated_closures_enabled
    end

    sig { returns(T::Boolean) }
    def ghas_purchased
      repository.owner&.advanced_security_purchased?
    end

    sig { override.returns(T::Boolean) }
    def restricted_by_security_configuration?
      false
    end

    sig { returns(T::Boolean) }
    def display_shield_icon?
      false
    end

  end
end
