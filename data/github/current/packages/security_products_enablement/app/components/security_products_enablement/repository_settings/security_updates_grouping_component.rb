# typed: strict
# frozen_string_literal: true

module SecurityProductsEnablement::RepositorySettings
  class SecurityUpdatesGroupingComponent < ServiceComponent # rubocop:disable ViewComponent/ComponentsHaveUnitTests

    sig { returns(T::Boolean) }
    def restricted?
      restricted_by_enterprise_policy? || restricted_by_security_configuration?
    end

    sig { override.returns(T::Boolean) }
    def restricted_by_enterprise_policy?
      # Careful readers will note that we are not checking if the user is an admin here.
      # That's because the user's admin status is checked when `data.dependabot_updates_enablement_status`
      # is computed. Long term that should probably move into here.
      T.let(!data.dependabot_security_updates_enabled, T::Boolean) && T.cast(data.dependabot_security_updates_blocked_by_policy, T::Boolean)
    end

    sig { override.returns(T::Boolean) }
    def restricted_by_security_configuration?
      return false unless has_enforced_security_configuration?
      T.let(!data.dependabot_security_updates_enabled, T::Boolean) && repository.security_configuration!.dependabot_security_updates != "not_set"
    end

    sig { returns(T::Boolean) }
    def display_shield_icon?
      return false if has_mixed_restrictions?
      restricted_by_enterprise_policy? || restricted_by_security_configuration?
    end
  end
end
