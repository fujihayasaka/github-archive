# typed: strict
# frozen_string_literal: true

module Copilot::Settings
  class CopilotModelsSettingProvider < SettingsCore::SettingsProvider

    NAME = T.let("copilot_configurations".freeze, String)

    sig { void }
    def initialize
      super(NAME)
    end

    sig do
      override
      .params(
        names: T::Array[String],
        targetables: T::Array[Targeting::Targetable]
      )
      .returns(T::Array[SettingsCore::ISetting])
    end
    def settings_for(names, targetables)
      return [] unless names.any? { |name| name.start_with?("copilot.models.supported_models") }

      # If we are requesting the group, load all model settings and reuse them for any additionally requested model settings
      load_group = names.include?("copilot.models.supported_models")
      settings = targetables.flat_map do |targetable|
        next unless targetable.is_a?(Copilot::Organization) || targetable.is_a?(Copilot::Business)

        group = SettingsCore::MemorySetting.new("copilot.models.supported_models", nil, targetable, self.name) if load_group
        individual_models = Copilot::Policies::MODELS.filter_map do |model|
          load_individual = names.include?("copilot.models.supported_models.#{model.config_name}")
          next unless load_group || load_individual

          value = model.configuration_value(targetable)
          setting = SettingsCore::MemorySetting.new("copilot.models.supported_models.#{model.config_name}", value, targetable, self.name)
          # If we are returning a group, add the individual model setting to it
          group.group_settings << setting if group

          # If we are also loading this individual model setting, return it
          load_individual ? setting : nil
        end

        individual_models << group if group
        individual_models
      end

      settings.compact
    end

    sig { override.params(setting: SettingsCore::ISetting, actor: T.nilable(User)).returns(T.nilable(SettingsCore::ISetting)) }
    def update_setting(setting, actor: nil)
      target = setting.targetable
      return nil unless target.is_a?(Copilot::Organization) || target.is_a?(Copilot::Business)

      settings_to_update = if setting.is_group?
        setting.group_settings
      else
        [setting]
      end

      before = target.copilot_settings

      settings_to_update.each do |s|
        next unless s.name.start_with?("copilot.models.supported_models.")
        model_name = s.name.sub("copilot.models.supported_models.", "")
        model = Copilot::Policies::MODELS.find { |m| m.config_name == model_name }
        next unless model

        status = s.value
        next unless %w[enabled disabled no_policy unconfigured].include?(status)

        if model.value(target) == status || !model.available_for?(target)
          next
        end

        model.update!(target.configuration, status)
      end

      if target.is_a?(Copilot::Business)
        Copilot::BatchUpdateUserCacheSettingRulesJob.perform_later(target.id)
      elsif target.is_a?(Copilot::Organization)
        Copilot::BatchUpdateUserSettingsJob.perform_later(target.id)
      end
      if actor && before != (after = target.copilot_settings)
        target.instrument_settings_changed(actor, before, after)
      end

      setting
    end

    sig { override.returns(T::Array[Features]) }
    def supported_features
      [
        Features::WRITE_SETTINGS
      ]
    end
  end
end
