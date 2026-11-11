# typed: strict
# frozen_string_literal: true

module Mobile
  module Copilot
    module Paywall
      class FeatureComparisonSubsection
        TYPE = "feature_comparison_subsection"

        sig { params(hash: T::Hash[Symbol, T.untyped]).returns(FeatureComparisonSubsection) }
        def self.from_hash(hash)
          new(
            title: hash[:title].to_s,
            plan_rows: (hash[:plan_rows] || []).map { |item_hash| FeatureComparisonSubsectionItem.from_hash(item_hash) }
          )
        end

        sig { returns(String) }
        attr_reader :title

        sig { returns(T::Array[FeatureComparisonSubsectionItem]) }
        attr_reader :plan_rows

        sig do
          params(
            title: String,
            plan_rows: T::Array[FeatureComparisonSubsectionItem]
          ).void
        end
        def initialize(title:, plan_rows:)
          @title = title
          @plan_rows = plan_rows
        end

        sig { returns(T::Hash[Symbol, T.untyped]) }
        def to_hash
          {
            type: TYPE,
            title:,
            plan_rows: plan_rows.map(&:to_hash)
          }
        end

        sig { params(other: FeatureComparisonSubsection).returns(T::Boolean) }
        def eql?(other)
          self.class == other.class &&
            title == other.title &&
            plan_rows == other.plan_rows
        end
        alias :== eql?
      end
    end
  end
end
