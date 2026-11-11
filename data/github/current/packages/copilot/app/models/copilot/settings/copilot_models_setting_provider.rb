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
      override.params(
        names: T::Array[String],
        targetables: T::Array[Targeting::Targetable],
        cache: T::Hash[String, T.untyped] # rubocop:disable Sorbet/ForbidTUntyped
      ).returns(T::Array[SettingsCore::ISetting])
    end
    def settings_for(names, targetables, cache = {})
      names = names.filter { |name| name.start_with?("copilot.models.supported_models.") }
      return [] if names.empty?

      settings = targetables.flat_map do |targetable|
        next unless targetable.is_a?(Copilot::Organization) || targetable.is_a?(Copilot::Business)

        names.map do |name|
          model_key = name.sub("copilot.models.supported_models.", "")
          value = if builtin_model = Copilot::Policies::MODELS.find { |m| m.config_name == model_key }
            builtin_model.configuration_value(targetable)
          else
            # Assume registry model
            targetable.configuration.model_policy(model_key)
          end

          SettingsCore::MemorySetting.new(name, value, targetable, self.name)
        end
      end

      settings.compact
    end

    sig { override.params(settings: T::Array[SettingsCore::ISetting], actor: T.nilable(User)).returns(T::Array[SettingsCore::ISetting]) }
    def update_settings(settings, actor: nil)
      settings_by_target = settings.group_by(&:targetable)

      updated = settings_by_target.flat_map do |target, settings_to_update|
        next nil unless target.is_a?(Copilot::Organization) || target.is_a?(Copilot::Business)

        before = target.copilot_settings

        settings_to_update.each do |s|
          next unless s.name.start_with?("copilot.models.supported_models.")
          model_name = s.name.sub("copilot.models.supported_models.", "")

          status = s.value
          next unless %w[enabled disabled no_policy unconfigured].include?(status)

          model = Copilot::Policies::MODELS.find { |m| m.config_name == model_name }
          if model
            if model.value(target) == status || !model.available_for?(target)
              next
            end

            model.update!(target.configuration, status)
          else
            registry_model = Copilot::ModelsRegistryCache.for_entity(target).find { |m| m.model_key == model_name }
            next unless registry_model

            target.configuration.set_model_policy(model_name, status)
          end
        end

        if target.is_a?(Copilot::Business)
          Copilot::BatchUpdateUserCacheSettingRulesJob.perform_later(target.id)
        elsif target.is_a?(Copilot::Organization)
          Copilot::BatchUpdateUserSettingsJob.perform_later(target.id)
        end
        if actor && before != (after = target.copilot_settings)
          target.instrument_settings_changed(actor, before, after)
        end

        settings_to_update
      end

      updated.compact
    end

    sig { override.returns(T::Array[Features]) }
    def supported_features
      [
        Features::WRITE_SETTINGS
      ]
    end
  end
end
