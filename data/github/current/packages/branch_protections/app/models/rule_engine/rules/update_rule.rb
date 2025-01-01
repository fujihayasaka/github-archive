# typed: true
# frozen_string_literal: true

module RuleEngine
  module Rules
    class UpdateRule < RefUpdateRule

      def initialize
        super(rule_name: "update",
              display_name: "Restrict updates",
              description: "Only allow users with bypass permission to update matching refs.")
      end

      def is_user_configurable?(source = nil)
        true
      end

      sig { override.params(rule_config: RepositoryRuleConfiguration).returns(T::Array[Symbol]) }
      def ignore_update_types(rule_config)
        [:creation, :deletion]
      end

      def parameter_schema
        schema = ParameterSchema::Object.root
        schema.add_field(ParameterSchema::Field.new(name: "update_allows_fetch_and_merge", display_name: "Allow fork syncing",
          required: true, type: :boolean, description: "Branch can pull changes from its upstream repository",
          visibility_fn: method(:is_allow_fork_syncing_param_visible?)))
        schema
      end

      sig { override.returns(String) }
      def minimum_ghes_version
        "3.11"
      end

      sig { override.params(context: RuleEvaluationContext, ref_update: Git::Ref::Update, rule_configs: T::Array[RepositoryRuleConfiguration]).returns(T::Array[RuleRun]) }
      def evaluate(context, ref_update, rule_configs)
        rule_configs.map do |rule_config|
          if ref_update.changed? && !(context.fetch_and_merge? && rule_config.param("update_allows_fetch_and_merge"))
            RuleRun.failure(rule_config: rule_config, ref_update: ref_update, message: "Cannot update this protected ref.")
          else
            RuleRun.success(rule_config: rule_config, ref_update: ref_update)
          end
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

        def update_allows_fetch_and_merge?(actor: nil)
          # fetch and merge is allowed if the user can either override or the config permits fetching and merging
          # all configs must pass this check
          enforced_rules_by_type("update", actor).all? { |config| config.param("update_allows_fetch_and_merge") }
        end

        def block_updates_enabled?
          configs_by_type("update").any?
        end
      end
    end
  end
end
