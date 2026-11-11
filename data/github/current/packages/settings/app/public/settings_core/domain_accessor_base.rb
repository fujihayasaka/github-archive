# typed: strict
# frozen_string_literal: true

module SettingsCore
  module DomainAccessorBase
    extend T::Helpers

    include Kernel

    abstract!

    sig do
      type_parameters(:U).params(
        targetable: Targeting::Targetable,
        definition_class: T::Class[SettingDefinition[T.untyped, T.type_parameter(:U)]],
        setting_name: T.nilable(String),
      ).returns(T.type_parameter(:U))
    end
    def get_effective_value(targetable, definition_class, setting_name: nil)
      definitions = definitions_by_class(definition_class)
      raise ArgumentError, "Definition not found for #{definition_class.name}" if definitions.empty?

      if setting_name.nil? && definitions.size > 1
        raise ArgumentError, "Multiple definitions found for #{definition_class.name}, please specify setting_name"
      end

      if setting_name && definitions.none? { |d| d.name == setting_name }
        raise ArgumentError, "Definition with name #{setting_name} not found for #{definition_class.name}"
      end

      definition = setting_name ? definitions.find { |d| d.name == setting_name } : definitions.first
      T.must(definition).get_result(targetable)
    end

    sig do
      type_parameters(:U).params(
        targetable: Targeting::Targetable,
        definition_class: T::Class[SettingDefinition[T.untyped, T.type_parameter(:U)]],
        setting_name: T.nilable(String),
      ).returns(T.type_parameter(:U))
    end
    def get_inherited_value(targetable, definition_class, setting_name: nil)
      definitions = definitions_by_class(definition_class)
      raise ArgumentError, "Definition not found for #{definition_class.name}" if definitions.empty?

      if setting_name.nil? && definitions.size > 1
        raise ArgumentError, "Multiple definitions found for #{definition_class.name}, please specify setting_name"
      end

      if setting_name && definitions.none? { |d| d.name == setting_name }
        raise ArgumentError, "Definition with name #{setting_name} not found for #{definition_class.name}"
      end

      definition = T.must(setting_name ? definitions.find { |d| d.name == setting_name } : definitions.first)
      graph = definition.get_result_graph(targetable)

      definition.finalize_value(graph.inherited_value)
    end

    # Returns ISetting objects for the given setting name and targetables.
    # Setting name can either be a setting or group name
    sig do
      params(
        targets: T::Array[Targeting::Targetable],
        name: String,
        include_groups: T::Boolean,
      ).returns(T::Array[ISetting])
    end
    def load_settings(targets, name, include_groups: true)
      # Load any groups that are part of the name
      groups = []
      if include_groups
        parts = name.split(".")
        parts.each_with_index do |_, index|
          group_names = T.must(parts[0..index]).join(".")
          group = group_by_name(group_names)
          groups << group if group
        end
      end

      names_to_lookup = groups.map(&:name)
      if definition = definition_by_name(name)
        names_to_lookup << definition.name
      end
      raise ArgumentError, "No setting or group found for name #{name}" if names_to_lookup.empty?

      providers.flat_map do |provider|
        provider.settings_for(names_to_lookup, targets)
      end
    end

    sig { params(setting: ISetting, actor: T.nilable(User)).returns(T::Boolean) }
    def update_setting(setting, actor: nil)
      provider = providers.find { |p| p.name == setting.provider_name }
      raise ArgumentError, "Provider not found for #{setting.provider_name}" if provider.nil?

      if provider.supported_features.exclude?(SettingsProvider::Features::WRITE_SETTINGS) &&
         provider.supported_features.exclude?(SettingsProvider::Features::WRITE_RULES)
        raise NotImplementedError, "Provider #{provider.name} does not support updating settings or rules"
      end

      if provider.supported_features.exclude?(SettingsProvider::Features::WRITE_SETTINGS) && setting.value.present?
        raise NotImplementedError, "Provider #{provider.name} does not support updating setting values"
      end

      if provider.supported_features.exclude?(SettingsProvider::Features::WRITE_RULES) && setting.rules.any?
        raise NotImplementedError, "Provider #{provider.name} does not support updating setting rules"
      end

      new_setting = provider.update_setting(setting, actor:)
      !new_setting.nil?
    end

    sig { returns(T::Array[SettingsProvider]) }
    def providers
      T.cast(self.class, ClassMethods).providers || []
    end

    sig { params(name: String).returns(T.nilable(SettingDefinition[T.untyped, T.untyped])) }
    def definition_by_name(name)
      definitions = T.cast(self.class, ClassMethods).settings_by_class&.values&.flatten || []
      definitions.find { |d| d.name == name }
    end

    sig { params(definition_class: T::Class[SettingDefinition[T.untyped, T.untyped]]).returns(T::Array[SettingDefinition[T.untyped, T.untyped]]) }
    def definitions_by_class(definition_class)
      T.cast(self.class, ClassMethods).settings_by_class&.[](definition_class) || []
    end

    sig { params(name: String).returns(T.nilable(SettingGroup[T.untyped, T.untyped])) }
    def group_by_name(name)
      T.cast(self.class, ClassMethods).setting_groups&.find { |g| g.name == name }
    end

    sig { params(group_class: T::Class[SettingGroup[T.untyped, T.untyped]]).returns(T::Array[SettingGroup[T.untyped, T.untyped]]) }
    def groups_by_class(group_class)
      T.cast(self.class, ClassMethods).setting_groups&.select { |g| g.is_a?(group_class) } || []
    end

    module ClassMethods
      include Kernel

      sig { returns(T.nilable(T::Hash[T::Class[SettingDefinition[T.untyped, T.untyped]], T::Array[SettingDefinition[T.untyped, T.untyped]]])) }
      attr_reader :settings_by_class

      sig { returns(T.nilable(T::Array[SettingGroup[T.untyped, T.untyped]])) }
      attr_reader :setting_groups

      sig { returns(T.nilable(T::Array[SettingsProvider])) }
      attr_reader :providers

      sig { params(setting_definition: SettingDefinition[T.untyped, T.untyped]).void }
      def register_setting(setting_definition)
        @settings_by_class ||= T.let({}, T.nilable(T::Hash[T::Class[SettingDefinition[T.untyped, T.untyped]], T::Array[SettingDefinition[T.untyped, T.untyped]]]))

        if @settings_by_class.any? { |_, v| v.map(&:name).include?(setting_definition.name) }
          raise ArgumentError, "Setting definition with name #{setting_definition.name} already registered"
        end

        if @setting_groups&.any? { |g| g.name == setting_definition.name }
          raise ArgumentError, "Setting definition name #{setting_definition.name} conflicts with existing group name"
        end

        if @settings_by_class.key?(setting_definition.class)
          T.must(@settings_by_class[setting_definition.class]) << setting_definition
        else
          @settings_by_class[setting_definition.class] = [setting_definition]
        end
      end

      sig { params(group: SettingGroup[T.untyped, T.untyped]).void }
      def register_group(group)
        @setting_groups ||= T.let([], T.nilable(T::Array[SettingGroup[T.untyped, T.untyped]]))
        if @setting_groups.any? { |g| g.name == group.name }
          raise ArgumentError, "Settings group with name #{group.name} already registered"
        end
        if @settings_by_class&.values&.flatten&.any? { |d| d.name == group.name }
          raise ArgumentError, "Settings group name #{group.name} conflicts with existing setting definition name"
        end

        @setting_groups << group

        group.definitions.each do |definition|
          if definition.is_a?(SettingGroup)
            register_group(definition)
          else
            register_setting(definition)
          end
        end
      end

      sig { params(provider: SettingsProvider).void }
      def register_provider(provider)
        @providers ||= T.let([], T.nilable(T::Array[SettingsProvider]))
        @providers << provider
      end
    end
    mixes_in_class_methods(ClassMethods)
  end
end
