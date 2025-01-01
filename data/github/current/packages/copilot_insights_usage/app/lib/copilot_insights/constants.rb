# typed: true
# frozen_string_literal: true

module CopilotInsights
  module Constants
    StringHash = T.type_alias { T::Hash[String, String] }
    VALID_PERIODS = %w[7d 14d 28d].freeze
    VALID_INTERVALS = %w[1d].freeze
    PARAM_DEFAULTS = T.let({ "period" => "28d", "interval" => "1d" }.freeze, StringHash)
    AFD_SAS_TOKEN_EXPIRY = 60.minutes.freeze
    DIRECT_SAS_TOKEN_EXPIRY = 10.minutes.freeze

    # GitHub cache TTL durations - set slightly shorter than the corresponding SAS expiry
    AFD_CACHE_TTL = 59.minutes.freeze
    DIRECT_CACHE_TTL = 9.minutes.freeze
  end
end
