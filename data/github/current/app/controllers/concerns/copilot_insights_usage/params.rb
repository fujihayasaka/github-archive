# typed: true
# frozen_string_literal: true

module CopilotInsightsUsage
  module Params
    extend T::Helpers
    extend ActiveSupport::Concern

    requires_ancestor { ActionController::Base }

    StringHash = T.type_alias { T::Hash[String, String] }
    VALID_PERIODS = %w[7d 14d 28d].freeze
    VALID_INTERVALS = %w[1d].freeze
    PARAM_DEFAULTS = T.let({ "period" => "28d", "interval" => "1d" }.freeze, StringHash)

    # Normalizes and stores canonical query params for use in responses
    def canonicalize_query_params
      period = VALID_PERIODS.include?(params[:period]) ? params[:period] : PARAM_DEFAULTS["period"]
      interval = VALID_INTERVALS.include?(params[:interval]) ? params[:interval] : PARAM_DEFAULTS["interval"]

      merged = {
        "period" => period,
        "interval" => interval
      }

      @canonical_params = T.let(merged.freeze, T.nilable(StringHash))
    end

    # Returns the number of days represented by the normalized period
    def days
      period = params[:period]
      return 28 unless period && VALID_PERIODS.include?(period)

      period.to_i
    end
  end
end
