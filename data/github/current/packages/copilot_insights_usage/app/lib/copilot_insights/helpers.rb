# typed: strict
# frozen_string_literal: true

module CopilotInsights
  module Helpers
    include Constants

    sig { params(params: T.untyped).returns(StringHash) }
    def canonicalize_copilot_query_params(params)
      period = VALID_PERIODS.include?(params[:period]) ? params[:period] : PARAM_DEFAULTS["period"]
      interval = VALID_INTERVALS.include?(params[:interval]) ? params[:interval] : PARAM_DEFAULTS["interval"]

      {
        "period" => period,
        "interval" => interval
      }.freeze
    end

    sig { params(params: T.untyped).returns(Integer) }
    def period_to_days(params)
      period = params[:period]
      return 28 unless period && VALID_PERIODS.include?(period)
      period.to_i
    end
  end
end
