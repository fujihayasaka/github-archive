# typed: true
# frozen_string_literal: true

module RuleEngine
  module Rules
    class LockBranchRule < RefUpdateRule

      def initialize
        super(rule_name: "lock_branch",
              display_name: "Lock branch",
              description: "Branch is read-only. Users cannot push to the branch.")
      end

      def parameter_schema
        schema = ParameterSchema::Object.root

        schema.add_field(ParameterSchema::Field.new(name: "lock_allows_fetch_and_merge", display_name: "Allow fork syncing",
          required: true, type: :boolean, description: "Branch can pull changes from its upstream repository.",
          visibility_fn: method(:is_allow_fork_syncing_param_visible?)))

        schema
      end

      # If branch is locked, then all ref updates are blocked unless it is explicitly a branch rename
      # Or this is within the context of a fork sync and fork syncing is allowed
      #
      # A branch rename sets "allow_deletion_policy_bypass" to true, when an actor is permitted to rename the branch
      # Fork syncing is allowed on a locked branch when "lock_allows_fetch_and_merge" is true
      sig { override.params(context: RuleEvaluationContext, ref_update: Git::Ref::Update, rule_configs: T::Array[RepositoryRuleConfiguration]).returns(T::Array[RuleRun]) }
      def evaluate(context, ref_update, rule_configs)
        if ref_update.deletion? && ref_update.try(:allow_deletion_policy_bypass?)
          rule_configs.map { |config| RuleRun.success(rule_config: config, ref_update: ref_update) }
        elsif ref_update.changed? && context.fetch_and_merge?
          rule_configs.map do |config|
            if config.param("lock_allows_fetch_and_merge")
              RuleRun.success(rule_config: config, ref_update: ref_update)
            else
              RuleRun.failure(rule_config: config, ref_update: ref_update, message: "Cannot change this locked branch")
            end
          end
        else
          rule_configs.map { |config| RuleRun.failure(rule_config: config, ref_update: ref_update, message: "Cannot change this locked branch") }
        end
      end

      sig { override.params(rule_config: RepositoryRuleConfiguration).returns(T::Boolean) }
      def blocks_new_direct_commits?(rule_config)
        true
      end

      def is_allow_fork_syncing_param_visible?(source)
        source.is_a?(Repository) && source.fork?
      end

      module StatusMethods
        extend T::Helpers

        requires_ancestor { BranchRuleEvaluator }

        def lock_branch_enabled?
          configs_by_type("lock_branch").any?
        end

        def lock_allows_fetch_and_merge?(actor: nil)
          # fetch and merge is allowed if the user can either override a lock or the config permits fetching and merging
          # all configs must pass this check
          configs_by_type("lock_branch").all? { |config| config.param("lock_allows_fetch_and_merge") || config.can_bypass?(actor, repository) }
        end

        def lock_branch_enforced_for?(actor:)
          configs_by_type("lock_branch").any? { |config| !config.can_bypass?(actor, repository) }
        end
      end

    end
  end
end
