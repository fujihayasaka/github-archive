# typed: strict
# frozen_string_literal: true

module CopilotInsightsCodeGeneration
  class MetricsCardData
    include GitHub::Memoizer
    include ActionView::Helpers::NumberHelper

    LOOKBACK_DAYS = 28

    sig { returns(CopilotInsights::Types::MetricsCardPayload) }
    def payload
      { data: data }
    end

    private

    sig { returns(CopilotInsights::Types::MetricsCardData) }
    memoize def data
      {
        averageSuggestedLinesCardData: "2.4k",
        averageAcceptedLinesCardData: "1.2k",
        acceptanceRateCardData: "80%"
      }
    end
  end
end
