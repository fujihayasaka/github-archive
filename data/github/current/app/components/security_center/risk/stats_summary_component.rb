# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module Risk
    class StatsSummaryComponent < ApplicationComponent

      TEST_SELECTOR = "security-center-risk-stats-summary"
      PERCENTAGE_TEST_SELECTOR = "security-center-risk-stats-summary-percentage"

      class Data < T::Struct
        const :title, String
        const :affected_percentage, Integer
        const :stats_data, T::Array[T.any(StatComponent::Data, RemoteStatComponent::Data)]
      end

      sig { returns(String) }; attr_reader :title
      sig { returns(Integer) }; attr_reader :affected_percentage
      sig { returns(T::Array[T.any(StatComponent::Data, RemoteStatComponent::Data)]) }; attr_reader :stats_data

      sig { params(data: Data).void }
      def initialize(data)
        @title = T.let(data.title, String)
        @affected_percentage = T.let(data.affected_percentage, Integer)
        @stats_data = T.let(data.stats_data, T::Array[T.any(StatComponent::Data, RemoteStatComponent::Data)])

        stat_components_data, remote_stat_components_data = stats_data.partition { |stat_data| stat_data.is_a?(SecurityCenter::Risk::StatComponent::Data) }
        @stat_components_data = T.let(stat_components_data, T::Array[T.any(StatComponent::Data, RemoteStatComponent::Data)])
        @remote_stat_components_data = T.let(remote_stat_components_data, T::Array[T.any(StatComponent::Data, RemoteStatComponent::Data)])
      end
    end
  end
end
