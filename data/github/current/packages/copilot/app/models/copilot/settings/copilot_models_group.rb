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
      super(NAME)
    end

    sig { override.returns(T::Array[SettingsCore::RuleEvaluator[SupportedEvaluationContexts]]) }
    def rule_handlers
      [
        SettingsCore::SimpleRuleMutator[SupportedEvaluationContexts].new("add") do |setting_name, current_value, rule|
          model_name = setting_name.sub("copilot.models.supported_models.", "")
          values = T.cast(rule.parameters["values"], T::Hash[String, String])
          if values[model_name]
            CopilotModelSetting::Value.from_serialized(values[model_name])
          else
            current_value
          end
        end,
      ]
    end
  end
end
