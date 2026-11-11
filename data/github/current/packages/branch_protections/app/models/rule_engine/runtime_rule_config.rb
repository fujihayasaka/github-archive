# typed: strict
# frozen_string_literal: true

module RuleEngine
  # In-memory implementation of IRuleConfig for non-ruleset rules.
  # Use this for rule configurations that are generated on the fly and not persisted in the database
  class RuntimeRuleConfig
    include IRuleConfig

    sig { override.returns(T::Hash[String, T.untyped]) }
    attr_reader :parameters

    sig { override.returns(String) }
    attr_reader :rule_type

    sig { override.returns(T.nilable(T::Array[String])) }
    attr_accessor :matching_ref_names

    sig { override.returns(T.nilable(T::Array[RuleEvent::EventAction])) }
    attr_accessor :matching_event_actions

    sig { override.returns(RuleProvider) }
    attr_reader :provider

    sig { override.returns(T.untyped) }
    attr_reader :source

    sig do
      params(
        rule_type: T.any(String, Symbol),
        source: T.untyped,
        provider: RuleProvider,
        parameters: T::Hash[T.any(String, Symbol), T.untyped],
        provider_id: T.nilable(Integer),
        matching_ref_names: T.nilable(T::Array[String]),
        lazy_parameters: T::Hash[String, T.proc.returns(T.untyped)],
        evaluate_mode: T::Boolean,
      ).void
    end
    def initialize(rule_type:, source:, provider:, parameters: {}, provider_id: nil, matching_ref_names: nil, lazy_parameters: {}, evaluate_mode: false)
      @rule_type = T.let(rule_type.to_s, String)
      @parameters = T.let(parameters.transform_keys(&:to_s), T::Hash[String, T.untyped])
      @source = source
      @provider_backing_id = provider_id
      @provider = provider
      @matching_ref_names = matching_ref_names
      @lazy_parameters = T.let(lazy_parameters.transform_keys(&:to_s), T::Hash[String, T.proc.returns(T.untyped)])
      @lazy_generated_parameters = T.let({}, T::Hash[String, T.untyped])
      @evaluate_mode = T.let(evaluate_mode, T::Boolean)
    end

    # Returns nil since provider-backed configs are not persisted
    sig { override.returns(T.nilable(Integer)) }
    def id
      nil
    end

    sig { override.returns(String) }
    def provider_name
      @provider.identifier
    end

    sig { override.returns(T.nilable(Integer)) }
    def provider_id
      @provider_backing_id
    end

    sig { override.returns(T.nilable(Integer)) }
    def history_id
      nil
    end

    sig { override.returns(T::Boolean) }
    def evaluate_mode?
      @evaluate_mode
    end

    sig { override.returns(T::Boolean) }
    def enabled?
      true
    end

    sig { override.params(parameter_name: String).returns(T.untyped) }
    def param(parameter_name)
      if parameters.has_key?(parameter_name)
        parameters[parameter_name]
      elsif @lazy_generated_parameters.has_key?(parameter_name)
        @lazy_generated_parameters[parameter_name]
      elsif @lazy_parameters.has_key?(parameter_name)
        @lazy_generated_parameters[parameter_name] = T.must(@lazy_parameters[parameter_name]).call
      end
    end

    sig { override.params(parameter_name: String).returns(T::Boolean) }
    def has_param(parameter_name) # rubocop:disable Naming/PredicatePrefix
      parameters.has_key?(parameter_name) ||
        @lazy_generated_parameters.has_key?(parameter_name) ||
        @lazy_parameters.has_key?(parameter_name)
    end
  end
end
