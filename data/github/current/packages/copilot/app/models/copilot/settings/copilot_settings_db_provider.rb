# typed: strict
# frozen_string_literal: true

module Copilot::Settings
  class CopilotSettingsDbProvider < SettingsCore::DefaultSettingsProvider

    NAME = T.let("copilot_settings".freeze, String)

    sig { void }
    def initialize
      super(NAME, Setting)
    end

    sig do
      override.params(
        names: T::Array[String],
        targetables: T::Array[Targeting::Targetable],
        cache: T::Hash[String, T.untyped] # rubocop:disable Sorbet/ForbidTUntyped
      ).returns(T::Array[SettingsCore::ISetting])
    end
    def settings_for(names, targetables, cache = {})
      # This provider only stores rules at the group level. Avoid querying for individual model settings.
      names = names.filter { |name| name == "copilot.models.supported_models" }
      super(names, targetables, cache)
    end

    sig { override.params(new_settings: T::Array[SettingsCore::ISetting], actor: T.nilable(User)).returns(T::Array[SettingsCore::ISetting]) }
    def update_settings(new_settings, actor: nil)
      updated_settings = super

      targets = Set.new
      updated_settings.each do |updated_setting|
        if updated_setting.name == "copilot.models.supported_models"
          targets << updated_setting.targetable
        end
      end
      targets.each do |target|
        if target.is_a?(Copilot::Business)
          Copilot::BatchUpdateUserCacheSettingRulesJob.perform_later(target.id)
        elsif target.is_a?(Copilot::Organization)
          Copilot::BatchUpdateUserSettingsJob.perform_later(target.id)
        end
      end

      updated_settings
    end
  end
end
