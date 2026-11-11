# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Fanout
    module Strategies
      module FeatureStrategyFactory
        extend T::Helpers
        final!

        FeatureStrategyType = T.type_alias do
          T.class_of(CodeScanningPullRequestAlert)
        end

        FEATURE_STRATEGY_MAPPINGS = T.let({
          Types::Feature::CodeScanningPullRequestAlert => CodeScanningPullRequestAlert
        }, T::Hash[Types::Feature, FeatureStrategyType])

        sig(:final) do
          params(
            feature: Types::Feature,
            tenant: T.any(::User, ::Organization, ::Business),
            owner_type: T.nilable(Types::Owner)
          ).returns(FeatureStrategy)
        end
        def self.from_feature(feature, tenant:, owner_type: nil)
          strategy_type = FEATURE_STRATEGY_MAPPINGS[feature]
          raise ArgumentError, "Unsupported feature: #{feature}" if strategy_type.nil?
          strategy_type.new(tenant:, owner_type:)
        end
      end
    end
  end
end
