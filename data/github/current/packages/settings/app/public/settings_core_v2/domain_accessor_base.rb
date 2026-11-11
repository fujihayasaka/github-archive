# typed: strict
# frozen_string_literal: true

module SettingsCoreV2
  module DomainAccessorBase
    extend T::Helpers
    extend ActiveSupport::Concern
    include GitHub::Memoizer

    include Kernel

    abstract!

    included do
      T.bind(self, T.class_of(GH::Domain::Base))

      # WrapPreloads breaks methods that can return both AR objects and non-AR objects in the same array
      # set to a method that will never use this to avoid it wrapping the rest of the domain
      decorate_with GH::Decorator::WrapPreloads, only: [:providers]
    end

    # Evaluate the effective value of many settings for a target resource
    sig do
      type_parameters(:Resource).params(
        targets_to_names: T::Hash[T.type_parameter(:Resource), T::Array[String]],
      ).returns(T::Hash[T.type_parameter(:Resource), T::Hash[String, T.untyped]])
    end
    def effective_value_bulk(targets_to_names)
      # preload all relevant settings
      load_settings(targets_to_names)

      targets_to_names.each_with_object({}) do |(target, names), acc|
        acc[target] = names.each_with_object({}) do |name, inner_acc|
          definition = definition_by_name(name)
          next unless definition

          value = effective_value(target, name, definition.class)
          inner_acc[name] = value
        end
      end
    end

    # Evaluate the effective value of a setting at a target resource.
    sig do
      type_parameters(:Resource, :Return).params(
        target: T.type_parameter(:Resource),
        setting_name: String,
        definition_class: T::Class[SettingDefinition[T.type_parameter(:Resource), T.all(BasicObject, T.type_parameter(:Return))]],
      ).returns(T.type_parameter(:Return))
    end
    def effective_value(target, setting_name, definition_class)
      definition = definition_by_name(setting_name)
      raise ArgumentError, "No definition found for #{setting_name}" unless definition.is_a?(definition_class)

      context = definition.resolver(self, target, setting_name).evaluate_setting

      current = context.current_value
      case current when nil; definition.default_value; else current end
    end

    # Get the allowed values for many settings and resources, if applicable
    sig do
      type_parameters(:Resource).params(
        targets_to_names: T::Hash[T.type_parameter(:Resource), T::Array[String]],
      ).returns(T::Hash[T.type_parameter(:Resource), T::Hash[String, T::Array[T.untyped]]])
    end
    def allowed_values_bulk(targets_to_names)
      load_settings(targets_to_names)

      targets_to_names.each_with_object({}) do |(target, names), acc|
        acc[target] = names.each_with_object({}) do |name, inner_acc|
          definition = definition_by_name(name)
          next unless definition

          values = allowed_values(target, name, definition.class)
          inner_acc[name] = values
        end
      end
    end

    # Get the allowed values for a setting at a target resource, if applicable
    sig do
      type_parameters(:Resource, :Return).params(
        target: T.type_parameter(:Resource),
        setting_name: String,
        definition_class: T::Class[SettingDefinition[T.type_parameter(:Resource), T.all(BasicObject, T.type_parameter(:Return))]],
      ).returns(T::Array[T.type_parameter(:Return)])
    end
    def allowed_values(target, setting_name, definition_class)
      definition = definition_by_name(setting_name)
      raise ArgumentError, "No definition found for #{setting_name}" unless definition.is_a?(definition_class)

      context = definition.resolver(self, target, setting_name).evaluate_setting

      context.current_allowed_values || definition.inheritance_priority
    end

    # Evaluate the inherited value of a setting from a parent resource.
    sig do
      type_parameters(:Resource, :Resource2, :Return).params(
        target: T.type_parameter(:Resource2),
        setting_name: String,
        definition_class: T::Class[SettingsCoreV2::SettingDefinition[T.any(T.type_parameter(:Resource), T.type_parameter(:Resource2)), T.all(BasicObject, T.type_parameter(:Return))]],
        parent: T.nilable(T.type_parameter(:Resource)),
      ).returns(T.type_parameter(:Return))
    end
    def inherited_value(target, setting_name, definition_class, parent: nil)
      definition = definition_by_name(setting_name)
      raise ArgumentError, "No definition found for #{setting_name}" unless definition.is_a?(definition_class)

      resolver = definition.resolver(self, target, setting_name)
      context = resolver.evaluate_setting

      resolver.inherited_value(context, parent) || definition.default_value
    end

    # Loads settings using an explicit mapping of resource → setting names.
    sig do
      params(
        targets_to_names: T::Hash[T.untyped, T::Array[String]],
      ).returns(T::Array[ISetting])
    end
    def load_settings(targets_to_names)
      all_names = targets_to_names.values.flatten.uniq
      names_to_lookup = all_names.select { |name| definition_by_name(name).present? }
      raise ArgumentError, "No setting found for names #{all_names.join(', ')}" if names_to_lookup.empty?

      validated = targets_to_names.transform_values { |ns| ns & names_to_lookup }
                                  .reject { |_, ns| ns.empty? }

      # filter out overrides
      override_matches = @overrides&.filter do |o|
        targets_to_names.any? { |target, names| resources_match?(o.resource, target) && names.include?(o.name) }
      end || []
      to_lookup = validated.to_h do |target, names|
        override_names = override_matches.filter_map { |o| o.name if resources_match?(o.resource, target) }

        [target, names - override_names]
      end

      # For each (target, setting_name), accumulate the settings produced by each
      # provider as { provider_name => ISetting }. A provider yields at most one
      # setting per (target, name), so this hash is built directly during loading
      # and passed to `combine_settings` without any later regrouping.
      settings_by_target_and_name = T.let(
        Hash.new { |h, k| h[k] = {} },
        T::Hash[[T.untyped, String], T::Hash[String, ISetting]],
      )

      providers.each do |provider|
        uncached = T.let({}, T::Hash[T.untyped, T::Array[String]])

        to_lookup.each do |target, target_names|
          target_names.each do |name|
            definition = definition_by_name(name)
            next unless definition&.providers_for(self)&.any? { |p| p.name == provider.name }

            entry = cache.get(provider.name, name, target)
            if entry == :miss
              (uncached[target] ||= []) << name
            elsif entry.is_a?(ISetting)
              T.must(settings_by_target_and_name[[target, name]])[provider.name] = entry
            end
            # else: cached miss (nil) — provider has no setting for this (target, name)
          end
        end

        next if uncached.empty?

        results = provider.settings_for(uncached)
        uncached.each do |target, target_names|
          target_names.each do |name|
            match = results.find { |s| s.name == name && resources_match?(target, s.resource) }
            cache.put(provider.name, name, target, match)
            next unless match

            T.must(settings_by_target_and_name[[target, name]])[provider.name] = match
          end
        end
      end

      fetched_settings = settings_by_target_and_name.filter_map do |(_target, name), settings_by_provider|
        next if settings_by_provider.empty?
        next settings_by_provider.values.first if settings_by_provider.size == 1
        definition_by_name(name)&.combine_settings(settings_by_provider)
      end

      fetched_settings + override_matches
    end

    # Updates a single setting value, with optional actor for auditing. Returns true if the update succeeded.
    sig { params(resource: T.untyped, setting_name: String, new_value: T.untyped, actor: T.nilable(User)).returns(T::Boolean) }
    def update_setting_value(resource, setting_name, new_value, actor: nil)
      settings = load_settings({ resource => [setting_name] })

      setting = if settings.size == 0
        MemorySetting.new(setting_name, new_value, resource)
      else
        T.must(settings.first)
      end

      new_setting = MemorySetting.from_interface(setting)
      new_setting.value = new_value
      update_settings(resource, [new_setting], actor: actor)
    end

    # Updates many settings with optional actor for auditing. Returns true if the update succeeded.
    sig { params(resource: T.untyped, settings: T::Array[ISetting], actor: T.nilable(User)).returns(T::Boolean) }
    def update_settings(resource, settings, actor: nil)
      raise ArgumentError, "All settings must have the same resource" unless settings.all? { |s| resources_match?(s.resource, resource) }

      # filter out any invalid settings
      if settings.any? { |s| !s.value.nil? }
        targets_to_names = { resource => settings.filter { |s| !s.value.nil? }.map(&:name).uniq }
        allowed_values = allowed_values_bulk(targets_to_names)
        settings = settings.filter do |setting|
          definition = definition_by_name(setting.name)
          next false unless definition
          parsed_value = definition.coerce_value(resource, setting.value)
          raise ArgumentError, "Invalid value for #{setting.name}: #{setting.value}" if setting.value.present? && parsed_value.nil?

          allowed = allowed_values.dig(resource, setting.name)
          allowed.nil? || allowed.include?(parsed_value)
        end
      end

      pre_snapshots = SettingsSnapshot.snapshot_cached_settings(self, resource, settings)

      settings_by_provider = Hash.new { |h, k| h[k] = [] }

      settings_by_name = settings.group_by(&:name)
      settings_by_name.each do |name, grouped|
        if grouped.size > 1
          raise ArgumentError, "Multiple settings with name #{name} for the same resource are not allowed"
        end
        setting = T.must(grouped.first)

        definition = definition_by_name(name)
        unless definition
          raise ArgumentError, "No setting definition found for #{name}"
        end

        value_provider = definition.providers_for(self, feature: SettingProvider::Features::WRITE_SETTINGS).first
        rules_provider = definition.providers_for(self, feature: SettingProvider::Features::WRITE_RULES).first
        if !setting.value.nil? && value_provider.nil?
          raise ArgumentError, "No provider found for #{name} that supports updating setting values"
        end
        if setting.rules.any? && rules_provider.nil?
          raise ArgumentError, "No provider found for #{name} that supports updating setting rules"
        end

        if value_provider && rules_provider && value_provider != rules_provider
          # Split: value goes to one provider, rules (without value) go to the other.
          settings_by_provider[value_provider.name] << setting
          no_value_setting = MemorySetting.from_interface(setting)
          no_value_setting.value = nil
          settings_by_provider[rules_provider.name] << no_value_setting
        else
          # Same provider handles both, or only one is needed (no rules and only
          # a value provider, or no value and only a rules provider).
          target_provider = value_provider || rules_provider
          settings_by_provider[T.must(target_provider).name] << setting
        end
      end

      success = settings_by_provider.all? do |provider_name, grouped|
        provider = providers.find { |p| p.name == provider_name }
        next true unless provider

        updated = provider.update_settings(resource, grouped, actor: actor)

        if updated.any?
          clear_provider_cache(provider_name)
        end
        updated.size == grouped.size
      end

      enqueue_setting_changed_jobs(pre_snapshots, actor: actor) if success

      success
    end

    # Look up a definition by setting name.
    sig { params(name: String).returns(T.nilable(SettingDefinition[T.untyped, T.untyped])) }
    def definition_by_name(name)
      definitions = T.cast(self.class, ClassMethods).registered_definitions || []
      static_def = definitions.find { |d| d.setting_name == name }
      return static_def if static_def

      generators = T.cast(self.class, ClassMethods).registered_setting_generators || []
      generator = generators.find { |g| g.matches?(name) }
      generator&.generate_definition(name)
    end

    sig { returns(T::Array[SettingProvider]) }
    def providers
      T.cast(self.class, ClassMethods).providers || []
    end

    sig { params(provider_name: String, setting_name: T.nilable(String)).void }
    def clear_provider_cache(provider_name, setting_name: nil)
      cache.clear_provider(provider_name, setting_name:)
    end

    sig do
      type_parameters(:R)
      .params(
        overrides: T::Array[ISetting],
        block: T.proc.returns(T.type_parameter(:R)),
      )
      .returns(T.type_parameter(:R))
    end
    def with_settings_override(overrides, &block)
      old = @overrides
      @overrides = T.let(overrides, T.nilable(T::Array[ISetting]))
      yield
    ensure
      @overrides = old
    end

    # Returns definitions for all registered settings matching the given names.
    sig { params(setting_names: T::Array[String]).returns(T::Array[SettingDefinition[T.untyped, T.untyped]]) }
    def setting_definitions(setting_names)
      setting_names.filter_map do |name|
        definition = definition_by_name(name)
        next unless definition
        definition.definition_for(name)
      end
    end

    # Returns all known setting definitions, including those available to be known by registered generators.
    sig { returns(T::Array[SettingDefinition[T.untyped, T.untyped]]) }
    def known_setting_definitions
      static = T.cast(self.class, ClassMethods).registered_definitions || []
      generators = T.cast(self.class, ClassMethods).registered_setting_generators || []

      generated = []
      generators.each do |generator|
        generator.known_setting_names.each do |setting_name|
          generated << generator.generate_definition(setting_name)
        end
      end
      static + generated
    end

    sig { returns(T::Array[AttributeOverride]) }
    def attribute_overrides
      @attribute_overrides || []
    end

    sig do
      type_parameters(:R)
      .params(overrides: T::Array[AttributeOverride], block: T.proc.returns(T.type_parameter(:R)))
      .returns(T.type_parameter(:R))
    end
    def with_attribute_overrides(overrides, &block)
      old = @attribute_overrides
      @attribute_overrides = T.let(overrides, T.nilable(T::Array[AttributeOverride]))
      yield
    ensure
      @attribute_overrides = old
    end

    sig do
      params(
        setting_name: String,
        resource: T.untyped,
        previous_attributes: T::Array[AttributeOverride],
        actor: T.nilable(User),
      ).void
    end
    def enqueue_setting_changed_job(setting_name, resource, previous_attributes: [], actor: nil)
      definition = definition_by_name(setting_name)
      return unless definition
      return unless definition.needs_change_propagation?
      resource_def = definition.resource_definitions.find { |rd| rd.is_resource?(resource) }
      return unless resource_def

      setting_changed_job_class&.perform_later(
        resource_def.resource_type.serialize,
        resource.id,
        setting_name,
        old_attributes: previous_attributes.map { |attr| attr.to_hash(resource_def) },
        actor_id: actor&.id,
      )
    end

    protected

    # Returns the job class to use for setting changed notifications.
    sig { overridable.returns(T.nilable(T.class_of(SettingsCoreV2::SettingChangedJob))) }
    def setting_changed_job_class
      nil
    end

    private

    sig { returns(SettingsCache) }
    memoize def cache
      SettingsCache.new
    end

    sig { params(a: T.untyped, b: T.untyped).returns(T::Boolean) }
    def resources_match?(a, b)
      a_record = a.respond_to?(:internal_record) ? a.internal_record : a
      b_record = b.respond_to?(:internal_record) ? b.internal_record : b
      a_record == b_record
    end

    sig { params(snapshots: T::Array[T::Hash[Symbol, T.untyped]], actor: T.nilable(User)).void }
    def enqueue_setting_changed_jobs(snapshots, actor: nil)
      snapshots.each do |snapshot|
        next unless snapshot[:resource_id]

        setting_changed_job_class&.perform_later(
          snapshot[:resource_type],
          snapshot[:resource_id],
          snapshot[:setting_name],
          old_setting: snapshot[:old_setting],
          actor_id: actor&.id,
        )
      end
    end

    module ClassMethods
      include Kernel

      sig { returns(T.nilable(T::Array[SettingDefinition[T.untyped, T.untyped]])) }
      attr_reader :registered_definitions

      sig { returns(T.nilable(T::Array[SettingDefinitionGenerator])) }
      attr_reader :registered_setting_generators

      sig { returns(T.nilable(T::Array[SettingProvider])) }
      attr_reader :providers

      sig { params(definition: SettingDefinition[T.untyped, T.untyped]).void }
      def register_setting(definition)
        @registered_definitions ||= T.let([], T.nilable(T::Array[SettingDefinition[T.untyped, T.untyped]]))

        @registered_definitions << definition
      end

      sig { params(generator: SettingDefinitionGenerator).void }
      def register_setting_generator(generator)
        @registered_setting_generators ||= T.let([], T.nilable(T::Array[SettingDefinitionGenerator]))
        @registered_setting_generators << generator
      end

      sig { params(provider: SettingProvider).void }
      def register_provider(provider)
        @providers ||= T.let([], T.nilable(T::Array[SettingProvider]))
        @providers << provider
      end
    end
    mixes_in_class_methods(ClassMethods)
  end
end
