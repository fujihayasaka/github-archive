# typed: strict
# frozen_string_literal: true

module InProductTargeting
  module NudgeConcern
    extend ActiveSupport::Concern

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
  end
end
