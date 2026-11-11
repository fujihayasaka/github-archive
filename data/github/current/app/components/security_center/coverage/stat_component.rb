# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module Coverage
    class StatComponent < ApplicationComponent

      class DataItem < T::Struct
        const :aria_label, String
        const :count, Integer
        const :href, String
      end

      class Data < T::Struct
        const :feature_type, String
        const :eligible_count, Integer
        const :enabled, DataItem
        const :disabled, DataItem
      end

      TEST_SELECTOR = "security-center-coverage-stat"
      ENABLED_COUNT_TEST_SELECTOR = "security-center-coverage-stat-enabled-count"
      DISABLED_COUNT_TEST_SELECTOR = "security-center-coverage-stat-disabled-count"

      sig { returns(Data) }; attr_reader :data

      sig { params(data: Data).void }
      def initialize(data)
        @data = data
      end

      sig { returns(Integer) }
      def enabled_percentage
        return 0 if data.eligible_count.zero?
        data.enabled.count * 100 / data.eligible_count
      end

      sig { returns(Integer) }
      def disabled_percentage
        100 - enabled_percentage
      end
    end
  end
end
