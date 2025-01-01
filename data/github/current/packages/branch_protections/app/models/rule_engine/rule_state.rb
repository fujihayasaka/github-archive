# typed: strict
# frozen_string_literal: true

module RuleEngine
  # Shared logic for rule states
  # A rule state is a representation of the current set of rules that apply to a
  # targetable resource. Implementations can be used by the UI to provide best-effort
  # feedback to the user about what rules will be applied to a given action.
  # Since rules are not evaluated, implementations should not be used to authorize write operations.
  class RuleState
    extend T::Helpers
    include GitHub::BatchMethod
    extend RuleEngine::Timing

    abstract!

    sig { returns(Conditions::Targetable) }
    attr_reader :targetable

    sig { returns(T::Array[String]) }
    attr_reader :ignored_providers

    sig { params(targetable: Conditions::Targetable, ignored_providers: T::Array[String]).void }
    def initialize(targetable, ignored_providers: [])
      @targetable = targetable
      @ignored_providers = ignored_providers
    end

    batch_method(:rule_configs, T::Array[RepositoryRuleConfiguration]) do |rule_evaluators|
      trace_time("repository_rule_state.batch_rule_configs", span_attributes: { "gh.branch_protection_rule.repository_rule_state.target_count" => rule_evaluators.size }) do
        rule_evaluators = T.cast(rule_evaluators, T::Array[RepositoryRuleState])
        rules_by_evaluator = Hash.new { |h, k| h[k] = [] }

        RuleEngine::Evaluator::RULE_PROVIDERS.each do |provider|
          targetables = rule_evaluators.reject { |evaluator| evaluator.ignored_providers.include?(provider.identifier) }.map(&:targetable)
          rules_by_targetable = provider.rules_for_targetables(targetables)
          rules_by_targetable.each do |targetable, rules|
            rule_evaluators.each do |evaluator|
              if evaluator.targetable == targetable
                rules_by_evaluator[evaluator].concat(rules)
              end
            end
          end
        end

        rules_by_evaluator
      end
    end

    sig { params(type: String, include_evaluate: T::Boolean).returns(T::Array[RepositoryRuleConfiguration]) }
    def configs_by_type(type, include_evaluate: false)
      rule_configs.select do |config|
        config.rule_type == type && (include_evaluate || !config.evaluate_mode?)
      end
    end

    sig { params(type: String, actor: T.nilable(User)).returns(T::Array[RepositoryRuleConfiguration]) }
    def enforced_rules_by_type(type, actor)
      rule_configs.select do |config|
        config.rule_type == type && config.enabled? && !config.can_skip?(actor, targetable) && !config.can_bypass?(actor, targetable)
      end
    end
  end
end
