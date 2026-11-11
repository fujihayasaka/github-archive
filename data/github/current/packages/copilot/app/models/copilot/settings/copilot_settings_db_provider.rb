# typed: strict
# frozen_string_literal: true

module Copilot::Settings
  class CopilotSettingsDbProvider < SettingsCore::DefaultSettingsProvider

    NAME = T.let("copilot_settings".freeze, String)

    sig { void }
    def initialize
      super(NAME, Setting)
    end

    sig { override.params(new_setting: SettingsCore::ISetting, actor: T.nilable(User)).returns(T.nilable(SettingsCore::ISetting)) }
    def update_setting(new_setting, actor: nil)
      updated_setting = super

      if updated_setting && updated_setting.name == "copilot.models.supported_models"
        target = updated_setting.targetable
        if target.is_a?(Copilot::Business)
          Copilot::BatchUpdateUserCacheSettingRulesJob.perform_later(target.id)
        elsif target.is_a?(Copilot::Organization)
          Copilot::BatchUpdateUserSettingsJob.perform_later(target.id)
        end
      end

      updated_setting
    end
  end
end
