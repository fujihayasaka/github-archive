# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    module MergeConditions
      class PullRequestRulesCondition < Platform::Objects::Base
        description "Repository rules for merge condition"

        class << self
          delegate :async_api_can_access?, to: Platform::Interfaces::PullRequestMergeCondition
          delegate :async_viewer_can_see?, to: Platform::Interfaces::PullRequestMergeCondition
        end

        implements Interfaces::PullRequestMergeCondition

        field :rule_rollups, [Interfaces::RepositoryRuleRollup],
          description: "The rollup states of each rule type.",
          null: false

        def rule_rollups
          @object.async_rule_rollups.then do |rollups|
            ArrayWrapper.new(rollups)
          end
        end
      end
    end
  end
end
