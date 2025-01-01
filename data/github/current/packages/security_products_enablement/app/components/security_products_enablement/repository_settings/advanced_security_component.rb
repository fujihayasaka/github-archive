# typed: strict
# frozen_string_literal: true

module SecurityProductsEnablement::RepositorySettings
  class AdvancedSecurityComponent < ServiceComponent # rubocop:disable ViewComponent/ComponentsHaveUnitTests
    delegate :owner, to: :repository

    sig { returns(T::Boolean) }
    def restricted?
      restricted_by_enterprise_policy? ||
        restricted_by_security_configuration? ||
        (restricted_by_connect_error? && !is_currently_enabled?) || # Only restrict if disabled
        will_exceed_seat_allowance?
    end

    sig { override.returns(T::Boolean) }
    def restricted_by_enterprise_policy?
      # This checks `SecurityProduct::AdvancedSecurity` can_enable?/can_disable?
      # which will take the actor into account and allow bypasses if applicable:
      T.cast(data.advanced_security_blocked_by_policy, T::Boolean)
    end

    sig { returns(T::Boolean) }
    def restricted_by_connect_error?
      T.cast(data.advanced_security_blocked_by_connect_error, T::Boolean)
    end

    sig { returns(T::Boolean) }
    def blocked_by_changes_in_progress?
      data.advanced_security_blocked_by_in_progress_setting ||
        data.secret_scanning_blocked_by_in_progress_setting ||
        data.secret_scanning_push_protection_blocked_by_in_progress_setting
    end

    sig { returns(T::Boolean) }
    def will_exceed_seat_allowance?
      !is_currently_enabled? && data.advanced_security_will_exceed_seat_allowance
    end

    sig { override.returns(T::Boolean) }
    def restricted_by_security_configuration?
      # The enable_ghas feature is only true/false on SecurityConfigurations, it can not be not_set.
      # So we only need to check if there's an enforced SecurityConfiguration and not its value:
      enforced_security_configuration ? true : false
    end

    sig { returns(T::Boolean) }
    def is_currently_enabled?
      data.advanced_security_enabled
    end

    sig { returns(String) }
    def enablement_action
      is_currently_enabled? ? "Disable" : "Enable"
    end

    sig { returns(String) }
    def enablement_action_label
      "#{is_currently_enabled? ? "Dis" : "En"}able GitHub Advanced Security"
    end

    sig { returns(T::Boolean) }
    def display_shield_icon?
      return false if has_mixed_restrictions?

      restricted_by_enterprise_policy? || restricted_by_security_configuration?
    end

    sig { returns(T::Boolean) }
    def enablement_blocked?
      repository.advanced_security_locked_by_metered_usage?
    end
  end
end
