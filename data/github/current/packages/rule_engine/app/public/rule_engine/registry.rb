# typed: strict
# frozen_string_literal: true

module RuleEngine
  class Registry
    # Rule implementations keyed by rule_name
    sig { returns(T::Hash[String, BaseRule]) }
    attr_reader :rule_implementations

    sig { returns(T::Hash[String, BaseRule]) }
    attr_reader :companion_rules

    # Companion rules that run alongside a parent rule (keyed by parent rule_name)
    sig { returns(T::Hash[String, String]) }
    attr_reader :companion_rule_mappings

    sig { returns(T::Array[RuleProvider]) }
    attr_reader :rule_providers

    sig { void }
    def initialize
      @rule_implementations = T.let({}, T::Hash[String, BaseRule])
      @companion_rules = T.let({}, T::Hash[String, BaseRule])
      @companion_rule_mappings = T.let({}, T::Hash[String, String])
      @rule_providers = T.let([], T::Array[RuleProvider])
      @default_rules_by_target = T.let({}, T::Hash[String, T::Array[String]])
    end

    sig { params(rule_impl: BaseRule).void }
    def register_rule_implementation(rule_impl)
      @rule_implementations[rule_impl.rule_name] = rule_impl
    end

    sig { params(parent_rule_name: String, companion_impl: BaseRule).void }
    def register_companion_rule(parent_rule_name, companion_impl)
      @companion_rule_mappings[parent_rule_name] = companion_impl.rule_name
      @companion_rules[companion_impl.rule_name] = companion_impl
    end

    sig { params(provider: RuleProvider).void }
    def register_rule_provider(provider)
      @rule_providers << provider
    end

    sig { params(target: String, rule_names: T::Array[String]).void }
    def register_default_rules(target, rule_names)
      raise ArgumentError, "Default rule for target #{target} is already registered" if @default_rules_by_target.key?(target)
      rule_names.each do |rule_name|
        raise ArgumentError, "Default rule #{rule_name} is not a registered rule implementation" unless @rule_implementations.key?(rule_name)
      end
      @default_rules_by_target[target] = rule_names
    end

    sig { params(target: String).returns(T.nilable(T::Array[String])) }
    def default_rules_for_target(target)
      @default_rules_by_target[target]
    end

    # Look up a rule implementation or companion by rule_name
    sig { params(rule_type: String).returns(T.nilable(BaseRule)) }
    def rule_impl_for_rule_type(rule_type)
      @rule_implementations[rule_type] || @companion_rules[rule_type]
    end

    # All rule implementations including companions for the given rule type
    sig { params(rule_type: String).returns(T::Array[BaseRule]) }
    def rule_implementations_with_companions(rule_type)
      rules = T.let([], T::Array[T.nilable(BaseRule)])
      rules << @rule_implementations[rule_type]
      if companion_rule_name = @companion_rule_mappings[rule_type]
        rules << @companion_rules[companion_rule_name]
      end
      rules.compact
    end
  end
end
