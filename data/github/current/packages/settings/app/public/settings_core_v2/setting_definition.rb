# typed: strict
# frozen_string_literal: true

module SettingsCoreV2
  class SettingDefinition
    extend T::Generic

    # Resources this setting can be stored / evaluated on
    SupportedResource = type_member
    # Return type of setting evaluation
    ResultType = type_member { { upper: BasicObject } }

    # A unique name for this setting. Must be unique across the domain
    sig { returns(String) }
    attr_reader :setting_name

    # A human-friendly name for this setting, used in UIs
    sig { returns(String) }
    attr_reader :display_name

    # A human-friendly description for this setting, used in UIs
    sig { returns(String) }
    attr_reader :description

    # The type of control used to manipulate this setting in a UI
    sig { returns(ControlType) }
    attr_reader :control_type

    # An optional list of allowed values for this setting, used to populate dropdowns in UIs and validate inputs.
    sig { returns(T.nilable(T::Array[OptionDescriptor])) }
    attr_reader :options

    # An optional UI component that can be used to render this setting in a UI
    # This can be used to override default UI formatting
    sig { returns(T.nilable(String)) }
    attr_reader :ui_component

    # An optional hash of additional metadata that can be used by UIs
    sig { returns(T.nilable(T::Hash[String, T.untyped])) }
    attr_reader :metadata

    # The definition that provides evaluation logic for this setting.
    sig { returns(ResultType) }
    attr_reader :default_value

    # The order in which settings are inherited. Used to determine which setting takes precedence when a resource has multiple parents. The first value has the highest precedence, followed by the second, etc.
    sig { returns(T::Array[ResultType]) }
    attr_reader :inheritance_priority

    # The providers that can be used to store this setting
    sig { returns(T::Array[String]) }
    attr_reader :providers

    # The resources this setting applies to, and how to navigate the resource hierarchy for evaluation
    sig { returns(T::Array[ResourceDefinition]) }
    attr_reader :resource_definitions

    # An optional setting name that this setting should sync to when it changes. The target setting must be registered on the same domain and have a write-capable provider. Used for simple one-way syncing of effective values between settings
    sig { returns(T.nilable(String)) }
    attr_reader :syncs_to

    sig do
      params(
        setting_name: String,
        display_name: String,
        description: String,
        control_type: ControlType,
        default_value: ResultType,
        inheritance_priority: T::Array[ResultType],
        providers: T::Array[String],
        resource_definitions: T::Array[ResourceDefinition],
        options: T.nilable(T::Array[OptionDescriptor]),
        ui_component: T.nilable(String),
        metadata: T.nilable(T::Hash[String, T.untyped]),
        syncs_to: T.nilable(String),
      ).void
    end
    def initialize(setting_name:, display_name:, description:, control_type:, default_value:, inheritance_priority:, providers:, resource_definitions:, options: nil, ui_component: nil, metadata: nil, syncs_to: nil)
      @setting_name = setting_name
      @display_name = display_name
      @description = description
      @control_type = control_type
      @default_value = default_value
      @inheritance_priority = inheritance_priority
      @options = options
      @ui_component = ui_component
      @metadata = metadata
      @providers = providers
      @resource_definitions = resource_definitions
      @syncs_to = syncs_to
    end

    # Whether this setting has a hook that fires when effective values change.
    sig { overridable.returns(T::Boolean) }
    def has_setting_changed_hook?
      false
    end

    # Called for each resource whose effective value changed.
    sig { overridable.params(target: SupportedResource, old_value: ResultType, new_value: ResultType, user: T.nilable(User)).void }
    def setting_changed_hook(target, old_value, new_value, user = nil)
      # no-op by default
    end

    sig { overridable.params(name: String).returns(SettingDefinition[SupportedResource, ResultType]) }
    def definition_for(name)
      self
    end

    # Whether this setting participates in any post-write propagation
    # (hooks or sync). Used by the framework to decide whether to snapshot
    # pre-write effective values and enqueue change jobs.
    sig { returns(T::Boolean) }
    def needs_change_propagation?
      has_setting_changed_hook? || !syncs_to.nil?
    end

    sig { overridable.params(domain: DomainAccessorBase, feature: T.nilable(SettingProvider::Features)).returns(T::Array[SettingProvider]) }
    def providers_for(domain, feature: nil)
      domain.providers.filter { |p| (!feature || p.supported_features.include?(feature)) && providers.include?(p.name) }
    end

    sig { overridable.params(settings_by_provider: T::Hash[String, SettingsCoreV2::ISetting]).returns(SettingsCoreV2::ISetting) }
    def combine_settings(settings_by_provider)
      # By default, take the highest precedence setting
      T.must(settings_by_provider.sort_by { |provider_name, _| providers.index(provider_name) || Float::INFINITY }.last&.last)
    end

    # Called after this node's value has been applied and before descending contexts are evaluated. Use to modify the evaluation context, for example by restricting allowed values for descendants.
    sig { overridable.params(resource: SupportedResource, context: EvaluationContext[ResultType]).void }
    def modify_context(resource, context)
      # no-op by default
    end

    # Converts the input value into the expected type for this setting
    # Returns nil if the value is invalid and cannot be coerced
    sig { overridable.params(resource: SupportedResource, value: T.untyped).returns(T.nilable(ResultType)) }
    def coerce_value(resource, value)
      value
    end

    sig { overridable.returns(T::Array[RuleDefinition[ResultType]]) }
    def rule_definitions
      []
    end

    sig { params(domain: DomainAccessorBase, resource: SupportedResource, setting_name: String).returns(GraphResolver[SupportedResource, ResultType]) }
    def resolver(domain, resource, setting_name)
      GraphResolver[SupportedResource, ResultType].new(domain, resource, self, setting_name)
    end

    sig { params(resource: T.untyped).returns(T::Boolean) }
    def applies_to_resource?(resource)
      resource_definitions.any? { |rd| rd.is_resource?(resource) }
    end

    class ControlType < T::Enum
      enums do
        TOGGLE = new("toggle")
        SELECT = new("select")
        MULTI_SELECT = new("multi_select")
      end
    end

    class OptionDescriptor < T::Struct
      const :value, String
      const :label, String
      const :description, T.nilable(String)
    end

    sig { params(domain: T.nilable(DomainAccessorBase), resource: T.nilable(SupportedResource)).returns(T::Hash[Symbol, T.untyped]) }
    def ui_payload(domain: nil, resource: nil)
      result = {
        name: setting_name,
        displayName: display_name,
        description: description,
        controlType: control_type.serialize,
      }

      if options
        result[:options] = T.must(options).map do |opt|
          h = { value: opt.value, label: opt.label }
          h[:description] = opt.description if opt.description
          h
        end
      end

      if rule_definitions.any?
        result[:ruleDefinitions] = rule_definitions.map do |handler|
          {
            ruleType: handler.rule_type,
            appliesTo: handler.applies_to.serialize,
            parameterSchema: handler.parameter_schema,
            targetingAttributes: handler.targeting_attributes.map do |attr|
              {
                attribute: attr.attribute,
                displayName: attr.display_name,
                operations: attr.operations,
                valueType: attr.value_type.serialize,
              }
            end
          }
        end
      end

      if domain && resource
        result[:allowedValues] = domain.allowed_values(resource, setting_name, self.class)
      end

      result[:uiComponent] = ui_component if ui_component
      result[:metadata] = metadata if metadata

      result
    end
  end
end
