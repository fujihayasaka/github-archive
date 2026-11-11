# typed: strict
# frozen_string_literal: true

module Copilot::Settings
  class CopilotModelSetting < SettingsCore::SettingDefinition

    class Value < T::Enum
      enums do
        DISABLED = new("disabled")
        ENABLED = new("enabled")
        NO_POLICY = new("no_policy")
        UNCONFIGURED = new("unconfigured")
        FORCE_DISABLED = new("force_disabled")
      end
    end

    EvaluationContext = type_member { { fixed: T.nilable(Value) } }
    Result = type_member { { fixed: Value } } # For now, return Value. Eventually return just enabled/disabled boolean

    sig { returns(String) }
    attr_reader :model_name

    sig { params(model_name: String).void }
    def initialize(model_name)
      @model_name = model_name
    end

    # Compute the initial context from this node's parents. This is before we apply any rules or settings at this node.
    # A user can have multiple parent organizations, each with their own policy for a given model.
    sig { override.params(parent_contexts: T::Array[EvaluationContext]).returns(EvaluationContext) }
    def context_from_parents(parent_contexts)
      if parent_contexts.empty?
        return nil
      end
      # Most restrictive policy wins for Enterprises
      if parent_contexts.include?(Value::FORCE_DISABLED)
        Value::FORCE_DISABLED
      # Least restrictive policy wins for Organizations
      elsif parent_contexts.include?(Value::ENABLED)
        Value::ENABLED
      elsif parent_contexts.include?(Value::NO_POLICY)
        Value::NO_POLICY
      elsif parent_contexts.include?(Value::DISABLED)
        Value::DISABLED
      else
        Value::UNCONFIGURED
      end
    end

    # Incorporate any setting values at this node into the context
    # This is run after we apply rules from the parent
    sig { override.params(evaluation_graph: SettingsCore::Graph[EvaluationContext], context: EvaluationContext).returns(EvaluationContext) }
    def evaluate_at_resource(evaluation_graph, context)
      setting_values = evaluation_graph.setting_values.compact
      raise ArgumentError, "Only one setting value allowed" if setting_values.size > 1
      return context if setting_values.empty?

      model_status = Value.from_serialized(setting_values.first)

      # Most restrictive policy wins for Business
      if evaluation_graph.node.internal_record.is_a?(Business) && model_status == Value::DISABLED
        return Value::FORCE_DISABLED
      # Only use the value set at this node if the parent node allows us to
      elsif context.nil? || context == Value::NO_POLICY || (!T.unsafe(evaluation_graph.node).feature_flag_enabled?(:copilot_unconfigured_is_inherited, default: false) && context == Value::UNCONFIGURED)
        return model_status
      end

      context
    end

    sig { override.params(evaluation_context: EvaluationContext).returns(Result) }
    def finalize_value(evaluation_context)
      return default_value unless evaluation_context.present?

      # FORCE_DISABLED is only used internally to represent the most restrictive policy
      # Strip it out before returning the final value
      evaluation_context == Value::FORCE_DISABLED ? Value::DISABLED : evaluation_context
    end

    sig { override.returns(Result) }
    def default_value
      Value::UNCONFIGURED
    end

    sig { override.returns(String) }
    def name
      "copilot.models.supported_models.#{@model_name}"
    end

    sig { override.returns(SettingsCore::DomainAccessorBase) }
    def domain
      CopilotDomain.domain.settings
    end
  end
end
