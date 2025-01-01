# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module Risk
    class StatComponent < ApplicationComponent

      TEST_SELECTOR = "security-center-risk-stat"
      COUNT_TEST_SELECTOR = "security-center-risk-stat-count"

      class DataItem < T::Struct
        const :aria_label, String
        const :name, String
        const :color_key, T.nilable(Symbol)
        const :count, Integer
        const :percentage, Integer
        const :href, T.nilable(String)
      end

      class Data < T::Struct
        const :title, String
        const :count, Integer
        const :href, String
        const :items, T::Array[DataItem]
      end

      sig { returns(String) }; attr_reader :title
      sig { returns(Integer) }; attr_reader :count
      sig { returns(String) }; attr_reader :href
      sig { returns(T::Array[DataItem]) }; attr_reader :items

      sig { params(data: Data).void }
      def initialize(data)
        @title = T.let(data.title, String)
        @count = T.let(data.count, Integer)
        @href = T.let(data.href, String)
        @items = T.let(data.items, T::Array[DataItem])
      end

      sig { params(item: DataItem).returns(T.nilable(T::Hash[Symbol, T.nilable(T.any(Symbol, String))])) }
      def color_args(item)
        case item.color_key
        when :critical
          { bg: :danger_emphasis }
        when :high
          { bg: :severe_emphasis }
        when :medium, :moderate
          { bg: :attention_emphasis }
        when :low, :unaffected
          { bg: nil, style: "background-color: var(--fgColor-muted, var(--color-fg-subtle));" }
        when :informational, :affected
          { bg: :accent_emphasis }
        else
          { bg: nil }
        end
      end
    end
  end
end
