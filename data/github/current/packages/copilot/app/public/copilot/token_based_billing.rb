# typed: strict
# frozen_string_literal: true

module Copilot
  # Shared helper for TBB (Token Based Billing) enablement.
  #
  # Both user-level and org-level TBB calculations share the same date-based
  # launch gating. This module extracts that shared logic so callers don't
  # reimplement it.
  #
  # Usage:
  #   # Org-initiated (pass org as billable_owner):
  #   enabled, reason = TokenBasedBilling.enabled?(billable_owner: copilot_org)
  #
  #   # User-initiated (pass user and optional billable_owner):
  #   enabled, reason = TokenBasedBilling.enabled?(
  #     user: copilot_user,
  #     billable_owner: limiter_billable_owner,
  #   )
  module TokenBasedBilling
    # Result type for enabled?.
    # - [true, nil]     — TBB is enabled
    # - [false, String] — TBB is not enabled, with reason
    Result = T.type_alias { [T::Boolean, T.nilable(String)] }

    # Runs the shared core gate pipeline for TBB eligibility.
    #
    # Accepts an optional user and/or billable_owner. Flag checks are OR'd across
    # whichever actors are present. At least one must be provided.
    sig do
      params(
        billable_owner: T.nilable(T.any(Copilot::User, Copilot::Organization, Copilot::Business)),
      ).returns(Result)
    end
    def self.enabled?(billable_owner: nil)
      # 1. Emergency skip
      if flag_enabled_on_any?(:copilot_skip_token_based_billing_check_dotcom, billable_owner)
        return [false, "Skip flag enabled"]
      end

      # 2. TBB flag (uses include_parents on billable_owner to check parent business)
      unless flag_enabled_on_any?(:copilot_token_based_billing, billable_owner)
        return [false, "copilot_token_based_billing flag not enabled"]
      end

      # 3. Yearly subscribers are not on TBB
      return [false, "Yearly subscribers not on TBB"] if billable_owner.is_a?(Copilot::User) && Copilot::Authorization::AccessLoader::YEARLY_ACCESS_TYPES.include?(billable_owner.access_type)

      # 4. Internal bypass for date checks
      #
      #    Internal bypass for TBB date checks make sure we disable FF before launch.
      if flag_enabled_on_any?(:copilot_internal_bypass_tbb_date_checks, billable_owner)
        return [true, nil]
      end

      # 5. Launch date gate
      #
      #    If we want to launch on June 1, 2026 set flag to be 1.52% actors enabled
      #    To calculate in ruby use: Date.new(2026, 6, 1).yday / 100.0
      launch_date = fetch_date_from_feature_flag(:copilot_tbb_launch_date_ordinal_as_actor_percent_float)
      return [false, "copilot_tbb_launch_date_ordinal_as_actor_percent_float not present"] unless launch_date.present?

      # 6. Past launch date → TBB
      return [true, nil] if current_date >= launch_date

      [false, "Not past launch date (#{launch_date})"]
    rescue StandardError => e
      GitHub.logger.error("Error determining token based billing eligibility for billable_owner #{billable_owner&.id}", exception: e)
      [false, "Error determining token based billing eligibility"]
    end

    # Checks if a flag is enabled on any of the provided actors (OR logic).
    # Uses include_parents on billable_owner to traverse org→business hierarchy.
    sig do
      params(
        flag_name: Symbol,
        billable_owner: T.nilable(T.any(Copilot::Organization, Copilot::Business, Copilot::User)),
      ).returns(T::Boolean)
    end
    private_class_method def self.flag_enabled_on_any?(flag_name, billable_owner)
      billable_owner&.feature_flag_enabled_include_parents?(flag_name, default: false) ||
        FeatureFlag.vexi.enabled?(flag_name, default: false) || # check if fully enabled even if no billable owner
        false
    end

    sig { returns(Date) }
    def self.current_date
      Time.current.in_time_zone("UTC").to_date
    end

    sig { params(flag_name: Symbol).returns(T.nilable(Date)) }
    def self.fetch_date_from_feature_flag(flag_name)
      begin
        day_of_year_float = FeatureFlag.vexi.percentage_of_actors_value_or_raise(flag_name) # rubocop:disable GitHub/FeatureManagement/NoVexiNonStandardUsage
      rescue
        return nil
      end

      # protect against floating point precision issues by converting to BigDecimal before multiplying
      # (e.g., 1.14 * 100 = 113.999... instead of 114)
      day_of_year = (day_of_year_float.to_d * 100).to_i
      return nil unless day_of_year > 0

      Date.ordinal(2026, day_of_year).in_time_zone("UTC").to_date
    end
  end
end
