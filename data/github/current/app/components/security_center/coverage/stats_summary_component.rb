# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module Coverage
    class StatsSummaryComponent < ApplicationComponent

      TEST_SELECTOR = "security-center-coverage-stats-summary"
      PERCENTAGE_TEST_SELECTOR = "security-center-coverage-stats-summary-percentage"

      class Data < T::Struct
        const :title, String
        const :enabled_percentage, Integer
        const :stats_data, T::Array[StatComponent::Data]
      end

      sig { params(data: Data).void }
      def initialize(data)
        @title = T.let(data.title, String)
        @enabled_percentage = T.let(data.enabled_percentage, Integer)
        @stat_components_data = T.let(data.stats_data, T::Array[StatComponent::Data])
      end
    end
  end
end
