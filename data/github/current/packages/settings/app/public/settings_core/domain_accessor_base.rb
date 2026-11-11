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
        setting_name: String,
      ).returns(T.type_parameter(:U))
    end
    def get_effective_value(targetable, definition_class, setting_name)
      definitions = definitions_by_class(definition_class)
      raise ArgumentError, "Definition not found for #{definition_class.name}" if definitions.empty?

      if (definition = definitions.find { |d| d.matches_setting?(setting_name) }).nil?
        raise ArgumentError, "Definition with name #{setting_name} not found for #{definition_class.name}"
      end

      definition.get_result(targetable, setting_name)
    end

    sig do
      type_parameters(:U).params(
        targetable: Targeting::Targetable,
        definition_class: T::Class[SettingDefinition[T.untyped, T.type_parameter(:U)]],
        setting_name: String,
      ).returns(T.type_parameter(:U))
    end
    def get_inherited_value(targetable, definition_class, setting_name)
      definitions = definitions_by_class(definition_class)
      raise ArgumentError, "Definition not found for #{definition_class.name}" if definitions.empty?

      if (definition = definitions.find { |d| d.matches_setting?(setting_name) }).nil?
        raise ArgumentError, "Definition with name #{setting_name} not found for #{definition_class.name}"
      end

      graph = definition.get_result_graph(targetable, setting_name)

      definition.finalize_value(graph.inherited_value)
    end

    # Returns ISetting objects for the given setting name and targetables.
    # Setting name can either be a setting or group name
    sig do
      params(
        targets: T::Array[Targeting::Targetable],
        names: T::Array[String],
        include_groups: T::Boolean,
      ).returns(T::Array[ISetting])
    end
    def load_settings(targets, names, include_groups: true)
      # Load any groups that are part of the name
      groups = []
      if include_groups
        names.each do |name|
          parts = name.split(".")
          parts.each_with_index do |_, index|
            group_names = T.must(parts[0..index]).join(".")
            group = group_by_name(group_names)
            groups << group if group
          end
        end
      end

      names_to_lookup = groups.map(&:name)
      names.each do |name|
        if definition_by_name(name).present?
          names_to_lookup << name
        end
      end
      raise ArgumentError, "No setting or group found for names #{names.join(', ')}" if names_to_lookup.empty?

      providers.flat_map do |provider|
        provider.settings_for(names_to_lookup, targets, provider_cache[provider.name])
      end
    end

    sig { params(settings: T::Array[ISetting], actor: T.nilable(User)).returns(T::Boolean) }
    def update_settings(settings, actor: nil)
      settings_by_provider = settings.group_by(&:provider_name)
      settings_by_provider.all? do |provider_name, settings|
        provider = providers.find { |p| p.name == provider_name }
        raise ArgumentError, "Provider not found for #{provider_name}" if provider.nil?

        if provider.supported_features.exclude?(SettingsProvider::Features::WRITE_SETTINGS) &&
          provider.supported_features.exclude?(SettingsProvider::Features::WRITE_RULES)
          raise NotImplementedError, "Provider #{provider.name} does not support updating settings or rules"
        end

        if provider.supported_features.exclude?(SettingsProvider::Features::WRITE_SETTINGS) && settings.any? { |s| s.value.present? }
          raise NotImplementedError, "Provider #{provider.name} does not support updating setting values"
        end

        if provider.supported_features.exclude?(SettingsProvider::Features::WRITE_RULES) && settings.any? { |s| s.rules.any? }
          raise NotImplementedError, "Provider #{provider.name} does not support updating setting rules"
        end

        new_settings = provider.update_settings(settings, actor:)
        if new_settings.any?
          clear_provider_cache(provider.name)
        end
        new_settings.size == settings.size
      end
    end

    sig { returns(T::Array[SettingsProvider]) }
    def providers
      T.cast(self.class, ClassMethods).providers || []
    end

    sig { params(name: String).returns(T.nilable(SettingDefinition[T.untyped, T.untyped])) }
    def definition_by_name(name)
      definitions = T.cast(self.class, ClassMethods).settings_by_class&.values&.flatten || []
      definitions.find { |d| d.matches_setting?(name) }
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

    sig { params(provider_name: String).void }
    def clear_provider_cache(provider_name)
      provider_cache.delete(provider_name)
    end

    private

    # A request-level cache for settings providers to use
    sig { returns(T::Hash[String, T.untyped]) }
    def provider_cache
      @provider_cache ||= T.let(Hash.new { |h, k| h[k] = {} }, T.nilable(T::Hash[String, T::Hash[String, T.untyped]]))
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

        @setting_groups << group
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
