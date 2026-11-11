# typed: strict
# frozen_string_literal: true

module RuleEngine

  # Abstract base class for all rule implementations
  class RefUpdateRule < BulkRunnableRule
    abstract!

    sig { params(rule_name: String, display_name: String, description: T.nilable(String), feature_flag: T.nilable(Symbol), beta: T::Boolean, beta_api_note: T::Boolean).void }
    def initialize(rule_name:, display_name:, description: nil, feature_flag: nil, beta: false, beta_api_note: false)
      super(rule_name:, display_name:, description:, feature_flag:, beta:, beta_api_note:)
    end

    sig { overridable.params(context: RuleEvaluationContext, rule_configs_by_ref_update: T::Hash[Git::Ref::Update, T::Array[RepositoryRuleConfiguration]]).returns(T::Array[RuleRun]) }
    def bulk_evaluate(context, rule_configs_by_ref_update)
      rule_configs_by_ref_update.flat_map do |ref_update, policies|
        evaluate(context, ref_update, policies)
      end
    end

    sig { overridable.params(context: RuleEvaluationContext, ref_update: Git::Ref::Update, rule_configs: T::Array[RepositoryRuleConfiguration]).returns(T::Array[RuleRun]) }
    def evaluate(context, ref_update, rule_configs)
      raise NotImplementedError
    end

    sig { override.params(event: RuleEvent, rule_configs_by_action: T::Hash[RuleEvent::EventAction, T::Array[RepositoryRuleConfiguration]]).returns(T::Array[RuleRun]) }
    def run_evaluation(event, rule_configs_by_action)
      return [] unless event.is_a?(GitEvent)
      rule_configs_by_action = T.cast(rule_configs_by_action, T::Hash[Git::Ref::Update, T::Array[RepositoryRuleConfiguration]])

      filter_and_run(event.legacy_evaluation_context, rule_configs_by_action)
    end

    sig do
      params(
        context: RuleEvaluationContext,
        rules_by_ref_update: T::Hash[Git::Ref::Update, T::Array[RepositoryRuleConfiguration]],
      ).returns(T::Array[RuleRun])
    end
    def filter_and_run(context, rules_by_ref_update)
      rule_runs = []

      # Filter out ref_updates that this policy ignores
      rules_by_ref_update = rules_by_ref_update.filter_map do |ref_update, relevant_policies|
        ignored_policies = relevant_policies.select { |pc| ref_update_ignored?(context, ref_update, pc) }
        rule_runs.concat(ignored_policies.map { |pc| RuleRun.success(rule_config: pc, ref_update: ref_update) })
        if ignored_policies.length == relevant_policies.length
          false
        else
          [ref_update, relevant_policies - ignored_policies]
        end
      end
      rules_by_ref_update = rules_by_ref_update.to_h
      if rules_by_ref_update.any?
        rule_runs.concat(bulk_evaluate(context, rules_by_ref_update))
      end

      rule_runs
    end

    # Indicates whether a rule would reject a new commit that has never been pushed to the server
    # Example: status checks cannot run against a never-seen commit, and therefore would fail
    #
    # This is only used to inform the UI how to render certain experiences like the blob editor
    sig { overridable.params(rule_config: RepositoryRuleConfiguration).returns(T::Boolean) }
    def blocks_new_direct_commits?(rule_config)
      false
    end

    # Allowed values: `creation`, `deletion`, `ref_in_merge_queue`
    sig { overridable.params(rule_config: RepositoryRuleConfiguration).returns(T::Array[Symbol]) }
    def ignore_update_types(rule_config)
      []
    end

    sig { params(context: RuleEvaluationContext, ref_update: Git::Ref::Update, rule_config: RepositoryRuleConfiguration).returns(T::Boolean) }
    def ref_update_ignored?(context, ref_update, rule_config)
      ignored_updated_types = ignore_update_types(rule_config)
      (ignored_updated_types.include?(:creation) && ref_update.creation?) || (ignored_updated_types.include?(:deletion) && ref_update.deletion?) ||
        (ignored_updated_types.include?(:ref_in_merge_queue) && context.ref_in_merge_queue?(ref_update))
    end
  end
end
