# typed: strict
# frozen_string_literal: true

module InProductTargeting
  module NudgeConcern
    extend ActiveSupport::Concern
    include HawaiiExperimentHelper

    class NudgeConfig < T::Struct
      const :nudge_type, Symbol
      const :nudge_id, Symbol
      const :nudge_feature_flag, T.nilable(Symbol)
      const :nudge_group, Symbol
      const :destination_key, Symbol
      const :expires, T.nilable(String), default: nil

      # Format the expires date for display in the format "Dec 13, 2025"
      # Returns nil if no expires date or if parsing fails
      sig { returns(T.nilable(String)) }
      def formatted_expires_date
        return nil unless expires.present?

        begin
          Date.parse(expires).strftime("%b\u202f%-d, %Y")
        rescue ArgumentError
          nil
        end
      end

      # Format the day after expires date for display in the format "Dec 14"
      # Returns nil if no expires date or if parsing fails
      sig { returns(T.nilable(String)) }
      def formatted_expires_next_day
        return nil unless expires.present?

        begin
          (Date.parse(expires) + 1.day).strftime("%b %-d")
        rescue ArgumentError
          nil
        end
      end
    end

    # Finds the most recent in-product targeting cohort data for a user since a specified date
    #
    # @param user_id [Integer] The ID of the user
    # @param cohort [String] The cohort identifier (e.g., "test cohort")
    # @param since [Date, String, Time] The date since when to look for data (will be converted to YYYY-MM-DD format)
    # @return [Hash, nil] The most recent JSON object with metadata, or nil if no matches found
    #
    # Example usage:
    #   find_in_product_targeting_cohort_data(user_id: 1, cohort: "test cohort", since: Date.yesterday)
    #   find_in_product_targeting_cohort_data(user_id: 1, cohort: "test cohort", since: "2024-06-01")
    #   find_in_product_targeting_cohort_data(user_id: 1, cohort: "test cohort", since: 1.week.ago)
    sig { params(user_id: Integer, cohort: String, since: T.any(Date, String, Time)).returns(T.nilable(T::Hash[String, T.untyped])) }
    def find_in_product_targeting_cohort_data(user_id:, cohort:, since:)
      # Convert the since parameter to YYYY-MM-DD format
      start_day = normalize_date_to_string(since)

      # Get all matches by day since the specified date
      matches_by_day = ::InProductTargeting.domain.matches_by_day(
        user_id: user_id,
        cohort: cohort,
        start_day: start_day
      )

      # Return nil if no matches found
      return nil if matches_by_day.empty?

      # Find the most recent day (datewise) and return its metadata
      most_recent_day = matches_by_day.keys.max
      return nil unless most_recent_day

      matches_by_day[most_recent_day]
    end

    # A|B test assignment for the Copilot CLI enabled dashboard nudge.
    # Returns 0 (treatment / install-command-picker UI) or 1 (control / existing CTA).
    #
    # Deterministic for a fixed user_id via HawaiiExperimentHelper. The `_0`/`_1`
    # feature flags force a variant (kill-switch / QA) without a deploy. When the
    # `hawaii_exp` flag is off or setup is invalid, `hawaii_experiment_variant`
    # returns -1, which normalizes to control. Shared by the enterprise and
    # organization dashboard nudge components so both arms bucket a user identically.
    # See the ADR:
    # https://github.com/github/in-product-messaging/blob/main/docs/dev/adr/nudge-ab-testing/ADR_nudge_ab_testing.md
    sig { params(user: User).returns(Integer) }
    def copilot_cli_enabled_dashboard_nudge_variant(user)
      variant = hawaii_experiment_variant(
        experiment_id: "ipm_accelerate_dashboard_copilot_cli_enabled_nudge",
        user_id: user.id,
        variant_count: 2,
      )

      # `_1` (control) takes precedence over `_0` (treatment) so the override is
      # explicit and only a single flag is evaluated rather than letting the last
      # assignment silently win when both flags are enabled.
      if user.feature_flag_enabled?(:ipm_accelerate_dashboard_copilot_cli_enabled_nudge_1, default: false)
        variant = 1
      elsif user.feature_flag_enabled?(:ipm_accelerate_dashboard_copilot_cli_enabled_nudge_0, default: false)
        variant = 0
      end

      variant.zero? ? 0 : 1
    end

    private

    # Normalizes various date formats to YYYY-MM-DD string format
    #
    # @param date_input [Date, String, Time] The date input to normalize
    # @return [String] The date in YYYY-MM-DD format
    # @raise [ArgumentError] If the date format is invalid
    sig { params(date_input: T.any(Date, String, Time)).returns(String) }
    def normalize_date_to_string(date_input)
      case date_input
      when Date
        date_input.strftime("%Y-%m-%d")
      when Time
        date_input.to_date.strftime("%Y-%m-%d")
      when String
        # Try to parse the string as a date and convert to standard format
        Date.parse(date_input).strftime("%Y-%m-%d")
      else
        # Sorbet: This branch is unreachable due to the sig, but required for Ruby completeness
        T.absurd(date_input)
      end
    rescue ArgumentError => e
      if date_input.is_a?(String)
        Kernel.raise(ArgumentError, "Invalid date format: #{date_input}. Error: #{e.message}")
      else
        Kernel.raise(e)
      end
    end

    # Finds the most recent in-product targeting cohort data for an enterprise
    #
    # @param enterprise_id [Integer] The ID of the enterprise
    # @param cohort [String] The cohort identifier
    # @param since [Date, String, Time] The date since when to look for data (default: 1 year ago)
    # @return [Hash, nil] The most recent JSON object with metadata, or nil if no matches found
    sig { params(enterprise_id: Integer, cohort: String, since: T.any(Date, String, Time)).returns(T.nilable(T::Hash[String, T.untyped])) }
    def find_in_product_targeting_enterprise_cohort_data(enterprise_id:, cohort:, since: 1.year.ago)
      start_day = normalize_date_to_string(since)

      matches_by_day = ::InProductTargeting.domain.matches_by_day(
        enterprise_id: enterprise_id,
        cohort: cohort,
        start_day: start_day
      )

      return nil if matches_by_day.empty?

      most_recent_day = matches_by_day.keys.max
      return nil unless most_recent_day

      matches_by_day[most_recent_day]
    end

    # Finds the most recent in-product targeting cohort data for an organization
    #
    # @param organization_id [Integer] The ID of the organization
    # @param cohort [String] The cohort identifier
    # @param since [Date, String, Time] The date since when to look for data (default: 1 year ago)
    # @return [Hash, nil] The most recent JSON object with metadata, or nil if no matches found
    sig { params(organization_id: Integer, cohort: String, since: T.any(Date, String, Time)).returns(T.nilable(T::Hash[String, T.untyped])) }
    def find_in_product_targeting_organization_cohort_data(organization_id:, cohort:, since: 1.year.ago)
      start_day = normalize_date_to_string(since)

      matches_by_day = ::InProductTargeting.domain.matches_by_day(
        organization_id: organization_id,
        cohort: cohort,
        start_day: start_day
      )

      return nil if matches_by_day.empty?

      most_recent_day = matches_by_day.keys.max
      return nil unless most_recent_day

      matches_by_day[most_recent_day]
    end

    # This is complicated due to the need to support previous enterprise account data that existed
    # when DFD was launched as a concept / the new normal
    # For clarity
    # dfd_trial? - seems to always evaluate to true if a users first step was creating a DFD trial to get to GHEC
    # no_trial_or_active_trial - Looks at trial_competion_status and at the very least evaluates to true if an enterprise is currently in a trial state. But may also evaluate to true if (we think) an enterprise was created before DFD trials were launched...
    sig { params(business: Business).returns(T::Boolean) }
    def is_business_in_active_dfd_trial?(business)
      !!(
        business.dfd_trial? &&
        business.trial_expires_at &&
        business.trial_expires_at >= Time.current &&
        business.no_trial_or_active_trial?
      )
    end
  end
end
