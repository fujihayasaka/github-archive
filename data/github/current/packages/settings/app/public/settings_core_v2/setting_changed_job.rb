# typed: strict
# frozen_string_literal: true

module SettingsCoreV2
  # Optional, implementable job used to sync settings between each other or run hooks when a setting changes
  class SettingChangedJob < ApplicationJob
    extend T::Helpers

    abstract!

    sig do
      params(
        resource_type: String,
        resource_id: Integer,
        setting_name: String,
        old_setting: T.nilable(T::Hash[String, T.untyped]),
        old_attributes: T.nilable(T::Array[T::Hash[String, T.untyped]]),
        actor_id: T.nilable(Integer),
      ).void
    end
    def perform(resource_type, resource_id, setting_name, old_setting: nil, old_attributes: nil, actor_id: nil)
      definition = domain.definition_by_name(setting_name)
      return unless definition&.needs_change_propagation?

      resource_def = definition.resource_definitions.find { |rd| rd.resource_type.serialize == resource_type }
      return unless resource_def
      resource = resource_def.from_id(resource_id)
      return unless resource

      resource_def = definition.resource_definitions.find { |rd| rd.is_resource?(resource) }
      return unless resource_def

      user = User.find_by(id: actor_id) if actor_id

      nodes_to_process = [resource].concat(resource_def.children(resource))
      nodes_to_process.each do |child|
        current_value = domain.effective_value(child, setting_name, definition.class)

        old_value = with_optional_settings_override(resource, setting_name, old_setting) do
          with_optional_attribute_overrides(definition, old_attributes) do
            domain.effective_value(child, setting_name, definition.class)
          end
        end

        next if current_value == old_value

        propagate_sync(definition, child, current_value, user) if definition.syncs_to
        definition.setting_changed_hook(child, old_value, current_value, user) if definition.has_setting_changed_hook?
      end
    end

    private

    sig do
      type_parameters(:R)
      .params(
        resource: T.untyped,
        setting_name: String,
        old_setting_json: T.nilable(T::Hash[String, T.untyped]),
        block: T.proc.returns(T.type_parameter(:R)),
      ).returns(T.type_parameter(:R))
    end
    def with_optional_settings_override(resource, setting_name, old_setting_json, &block)
      return yield if old_setting_json.nil?

      setting = MemorySetting.from_hash(old_setting_json, resource)
      domain.with_settings_override([setting], &block)
    end

    sig do
      type_parameters(:R)
      .params(
        definition: SettingDefinition[T.untyped, T.untyped],
        old_attributes: T.nilable(T::Array[T::Hash[String, T.untyped]]),
        block: T.proc.returns(T.type_parameter(:R)),
      ).returns(T.type_parameter(:R))
    end
    def with_optional_attribute_overrides(definition, old_attributes, &block)
      return yield if old_attributes.nil?

      attribute_overrides = old_attributes.map { |attr_hash| AttributeOverride.from_hash(attr_hash, definition) }.compact
      return yield if attribute_overrides.empty?

      domain.with_attribute_overrides(attribute_overrides, &block)
    end

    sig { abstract.returns(DomainAccessorBase) }
    def domain; end

    sig { params(source_definition: SettingDefinition[T.untyped, T.untyped], child: T.untyped, new_value: T.untyped, user: T.nilable(User)).void }
    def propagate_sync(source_definition, child, new_value, user)
      target_name = source_definition.syncs_to
      return unless target_name

      target_definition = domain.definition_by_name(target_name)
      unless target_definition
        GitHub.logger.error(
          "settings.sync.missing_target",
          "gh.settings.source_setting": source_definition.setting_name,
          "gh.settings.target_setting": target_name,
        )
        return
      end

      # T::Enum values serialize to their wire string; pass primitives through.
      serialized = new_value.respond_to?(:serialize) ? new_value.serialize : new_value

      # No-op when the new value equals the target evaluator's default. This
      # prevents pushing meaningless writes (e.g. NOT_SET) to external services.
      return if serialized == target_default_serialized(target_definition)

      domain.update_setting_value(child, target_name, serialized, actor: user)
    rescue => e
      GitHub.logger.error(
        "settings.sync.error",
        "gh.settings.source_setting": source_definition.setting_name,
        "gh.settings.target_setting": target_name,
        "gh.settings.error": e.message,
      )
    end

    sig { params(definition: SettingDefinition[T.untyped, T.untyped]).returns(T.untyped) }
    def target_default_serialized(definition)
      default = definition.default_value
      default.respond_to?(:serialize) ? default.serialize : default
    end
  end
end
