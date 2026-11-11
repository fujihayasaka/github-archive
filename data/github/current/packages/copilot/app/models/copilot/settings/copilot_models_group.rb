# typed: strict
# frozen_string_literal: true

module Copilot::Settings
  # A setting group that contains one setting per Copilot model
  class CopilotModelsGroup < SettingsCore::SettingGroup

    NAME = T.let("copilot.models.supported_models".freeze, String)

    SupportedEvaluationContexts = type_member { { fixed: T.nilable(CopilotModelSetting::Value) } }
    SupportedResults = type_member { { fixed: CopilotModelSetting::Value } }

    sig { void }
    def initialize
      super(
        NAME,
        Copilot::Policies::MODELS.map do |model|
          CopilotModelSetting.new(model.config_name)
        end
      )
    end

    sig { override.returns(T::Array[SettingsCore::RuleEvaluator[SupportedEvaluationContexts]]) }
    def rule_handlers
      [
        SettingsCore::SimpleRuleMutator[SupportedEvaluationContexts].new("add") do |definition, current_value, rule|
          next current_value unless definition.is_a?(CopilotModelSetting)

          values = T.cast(rule.parameters["values"], T::Hash[String, String])
          if values[definition.model_name]
            CopilotModelSetting::Value.from_serialized(values[definition.model_name])
          else
            current_value
          end
        end,
      ]
    end
  end
end
