# typed: strict
# frozen_string_literal: true

module Billing::TokenBasedBilling
  extend ActiveSupport::Concern

  AI_CREDITS_LAUNCH_DATE = T.let(Date.new(2026, 6, 1), Date)

  # Checks whether token-based billing (AI credits) should be enabled for an entity.
  # Requires the copilot_token_based_billing feature flag and a date on or after June 1, 2026.
  # For individual users, delegates to Copilot::User which has additional checks (e.g. yearly subscribers).
  sig { params(entity: ::Billing::Types::Account).returns(T::Boolean) }
  def billing_tbb_enabled?(entity)
    # For individual users, delegate to Copilot::User which has more granular checks
    return Copilot::User.new(entity).use_token_based_billing? if entity.is_a?(User) && entity.user?

    current = if T.unsafe(self).respond_to?(:current_user)
      T.cast(T.unsafe(self).current_user, T.nilable(User))
    end

    # Emergency kill switch to disable TBB if something is going terribly wrong
    return false if entity.feature_flag_enabled?(:copilot_skip_token_based_billing_check_dotcom, default: false) || current&.feature_flag_enabled?(:copilot_skip_token_based_billing_check_dotcom, default: false)
    # The copilot_token_based_billing feature flag will be enabled shortly before the scheduled launch date.
    # Do not allow access to TBB unless this flag is enabled
    return false unless entity.feature_flag_enabled?(:copilot_token_based_billing, default: false) || current&.feature_flag_enabled?(:copilot_token_based_billing, default: false)

    # Between the time that internal testing begins and the official launch date, we want to enable TBB but bypass
    # the date check for internal testers
    return true if entity.feature_flag_enabled?(:copilot_internal_bypass_tbb_date_checks, default: false) || current&.feature_flag_enabled?(:copilot_internal_bypass_tbb_date_checks, default: false)

    # Finally, enforce the launch date for everyone else (including internal testers who do not have the bypass flag enabled)
    Time.now.utc.to_date >= AI_CREDITS_LAUNCH_DATE
  end

  # Returns whether the given entity is an individual user with token-based billing (AI credits) enabled.
  sig { params(entity: ::Billing::Types::Account).returns(T::Boolean) }
  def billing_user_level_ai_units?(entity)
    return false unless entity.is_a?(User) && entity.user?
    Copilot::User.new(entity).use_token_based_billing?
  end
end
