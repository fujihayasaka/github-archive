# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module RepositoryRuleRollup
      include Platform::Interfaces::Base
      description "The rollup state of a specific rule type."

      required_capabilities [:mobile_only_schema_mask]

      orphan_types Platform::Objects::GenericRepositoryRuleRollup,
        Platform::Objects::RepositoryRules::RequiredDeploymentsRuleRollup,
        Platform::Objects::RepositoryRules::PullRequestRuleRollup,
        Platform::Objects::RepositoryRules::RequiredStatusChecksRuleRollup

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        object.async_repository.then do |repo|
          permission.typed_can_access?("Repository", repo)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        object.async_repository.then do |repo|
          permission.typed_can_see?("Repository", repo)
        end
      end

      created_at_field

      field :rule_type, Enums::RepositoryRuleType,
        description: "The type of rule rollup.",
        null: false

      field :display_name, String,
        description: "The display name of this rule type.",
        null: false

      field :description, String,
        description: "The description of this rule type.",
        null: true

      field :message, String,
        description: "The rollup result message of this rule.",
        null: true

      field :result, Enums::RepositoryRuleEvaluationResult,
        description: "The rollup result for this rule type.",
        null: false

      field :bypassable, Boolean,
        description: "Whether all rule runs for this type can be bypassed by the original pusher",
        null: false,
        visibility: :internal

      def bypassable
        @object.bypassable
      end

      field :rule_runs, Connections.define(Objects::RepositoryRuleRun),
        description: "The individual runs that make up this rollup.",
        null: false,
        connection: true

      def rule_runs
        ArrayWrapper.new(@object.rule_runs)
      end
    end
  end
end
