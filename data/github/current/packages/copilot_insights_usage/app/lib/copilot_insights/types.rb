# typed: strict
# frozen_string_literal: true

module CopilotInsights
  module Types
    MetricsCardPayload = T.type_alias do
      {
        data: MetricsCardData,
      }
    end

    MetricsCardData = T.type_alias do
      {
        linesChangedByAllModesCardData: String,
        agentContributionCardData: String,
        averageLinesDeletedByAgentCardData: String
      }
    end
  end
end
