# typed: true
# frozen_string_literal: true

module RuleEngine
  module Rules
    class LinearHistoryRule < RefUpdateRule

      def initialize
        super(rule_name: "required_linear_history",
              display_name: "Require linear history",
              description: "Prevent merge commits from being pushed to matching refs.")
      end

      def is_user_configurable?(source = nil)
        true
      end

      sig { override.params(rule_config: RepositoryRuleConfiguration).returns(T::Array[Symbol]) }
      def ignore_update_types(rule_config)
        [:deletion]
      end

      sig { override.returns(String) }
      def minimum_ghes_version
        "3.11"
      end

      # Linear history policy has no configuration: return the same result for each configuration
      sig { override.params(context: RuleEvaluationContext, ref_update: Git::Ref::Update, rule_configs: T::Array[RepositoryRuleConfiguration]).returns(T::Array[RuleRun]) }
      def evaluate(context, ref_update, rule_configs)
        # list any merge commits in this ref update's commit range.
        # deny the update if any results are returned.
        opts = { merges: true, limit: 1 }
        opts[:exclude_oids] = ref_update.before_oid unless ref_update.creation?

        oids = context.repository.rpc.rev_list(ref_update.after_oid, **opts)
        if oids.empty?
          rule_configs.map { |config| RuleRun.success(rule_config: config, ref_update: ref_update) }
        else
          rule_configs.map do |config|
            RuleRun.failure(
              rule_config: config,
              ref_update: ref_update,
              message: "This branch must not contain merge commits.",
              violations: oids.map { |oid| { candidate: oid } }
              )
          end
        end
      end

      module StatusMethods
        extend T::Helpers

        requires_ancestor { BranchRuleEvaluator }

        def required_linear_history_enabled?
          configs_by_type("required_linear_history").any?
        end

        def can_override_required_linear_history?(actor:, is_pull_request: false)
          configs = configs_by_type("required_linear_history")

          configs.all? do |config|
            provider = config.provider

            if provider.is_a?(RuleEngine::RuleProviders::RulesetRuleProvider)
              # If the linear history requirement is from a ruleset, the `is_pull_request`` parameter is relevant.
              ruleset = config.repository_ruleset
              if ruleset.present?
                next T.cast(provider, RuleEngine::RuleProviders::RulesetRuleProvider).
                  ruleset_bypass_allowed?(ruleset, actor, repository, is_pull_request:)
              end
            end

            # Otherwise this is from a protected_branch record, which don't have any concept of "bypass only via PR".
            provider.can_bypass?(config, actor, repository)
          end
        end

        def required_linear_history_enforced_for?(actor:, is_pull_request: false)
          return false unless required_linear_history_enabled?

          !can_override_required_linear_history?(actor:, is_pull_request:)
        end
      end
    end
  end
end
