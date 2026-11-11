# typed: false # rubocop:disable Sorbet/StrictSigil
# frozen_string_literal: true

# Sorbet does not handle ActiveSupport::Concern well, so we need to disable strictness here

module CustomPropertiesCore
  module DefinitionBase
    extend ActiveSupport::Concern
    extend T::Helpers
    include Instrumentation::Model
    include IPropertyDefinition

    abstract!

    sig { abstract.returns(T::Boolean) }
    def required?; end

    sig { abstract.returns(DefinitionBase) }
    def destroy!; end

    sig { abstract.returns(T::Boolean) }
    def present?; end

    sig { abstract.params(attributes: T.untyped).returns(DefinitionBase) }
    def update!(attributes); end

    AUDITABLE_FIELDS = T.let(%i[allowed_values config required value_type values_editable_by].freeze, T::Array[Symbol])

    included do
      before_save :ensure_uniq_of_allow_values, if: -> { self.allowed_values? }

      has_many :custom_property_values, class_name: self.value_class_name, foreign_key: "definition_id", dependent: :delete_all, inverse_of: :definition
      has_many :custom_property_usages, class_name: self.usage_class_name, foreign_key: "definition_id", dependent: :delete_all, inverse_of: :definition if respond_to?(:usage_class_name)

      after_create_commit :instrument_create
      after_update_commit :instrument_update, if: :saved_changes?

      # NOTE: Moving the instrument_destroy to commit callback causes a test failure in
      # packages/orgs/test/models/organization/delete_test.rb in enterprise mode,
      # related to the Organization being deleted once this callback in invoked
      after_destroy :instrument_destroy

      # Returns definitions defined at the given source level only
      scope :defined_by, ->(source) do
        source = T.cast(source, PropertySource)
        source_type = source.is_a?(::Business) ? :business : :org
        where(source_id: source.id, source_type: source_type)
      end

      # Returns all definitions for the source and its parent levels
      scope :for, ->(source) do
        source = T.cast(source, PropertySource)

        if source.is_a?(::Business)
          self.defined_by(source)
        else
          business = source.business
          relation = self.defined_by(source)
          relation = relation.or(self.defined_by(business)) if business.present?

          relation
        end
      end

      # Gets the property definitions for the provided organization ids
      #
      # organization_ids - the organization ids to get the definitions for
      scope :for_organization_ids, ->(organization_ids) { where(source_id: organization_ids, source_type: "org") }

      # Gets the property definitions similar to the provided property_name.
      #
      # property_name - the property name to search for
      scope :for_property_name_like, ->(property_name) { where("property_name LIKE ?", property_name.downcase) }

      validates_format_of :property_name, with: Public::NAME_VALID_CHARS_REGEX
      validates_length_of :property_name, minimum: 1, maximum: Public::MAX_PROPERTY_NAME_LENGTH
      validates :description, length: {
        maximum: Public::DESCRIPTION_MAX_LENGTH,
        too_long: "must be at most %{count} characters"
      }, allow_nil: true
      validates_presence_of :value_type
      validate :value_type_enabled
      validates_presence_of :values_editable_by
      validate :validate_allowed_values
      validate :validate_default_value_field
      validate :validate_regex

      enum :value_type, {
        string: 0,
        single_select: 1,
        true_false: 2,
        multi_select: 3,
        url: 4,
        actor: 5,
      }, suffix: true

      enum :source_type, {
        org: 0,
        business: 1,
      }, suffix: true

      batch_method(:source) do |definitions|
        org_definitions, business_definitions = definitions.partition { |definition| definition.source_type == "org" }

        org_sources = Organization.where(id: org_definitions.map(&:source_id)).index_by(&:id)
        org_definition_sources_hash = org_definitions.to_h { |definition| [definition, org_sources[definition.source_id]] }

        business_sources = Business.where(id: business_definitions.map(&:source_id)).index_by(&:id)
        business_definition_sources_hash = business_definitions.to_h { |definition| [definition, business_sources[definition.source_id]] }

        org_definition_sources_hash.merge(business_definition_sources_hash)
      end

      # Domain model class might implement `event_prefix` to customize the event prefix.
      # It is used to instrument promotions of property definitions.
      # Resulting event name will be `{event_prefix}.promote_to_enterprise`.
      # Defaults to the underscored definition model class name.
      #
      # @see CustomPropertiesBusinessDefinitionsManager#promote_definition
      def self.get_event_prefix
        respond_to?(:event_prefix) ? self.event_prefix : "#{self.name.underscore}"
      end
    end

    sig { returns(ActiveRecord::Associations::CollectionProxy) }
    def values
      custom_property_values
    end

    sig { override.returns(T.nilable(PropertyValue)) }
    def default_value
      config&.fetch("default_value", nil)
    end

    sig { params(params: T.untyped).void }
    def initialize(params)
      source = T.cast(params&.delete(:source), T.nilable(PropertySource))
      if source&.is_a?(::Organization) || source&.is_a?(::Business)
        @source = T.let(source, T.nilable(PropertySource))
        params[:source_id] = @source&.id
        params[:source_type] = @source&.is_a?(::Business) ? :business : :org
      end

      super(params)
    end

    sig { override.returns(T.nilable(String)) }
    def regex
      config&.fetch("regex", nil)
    end

    # Internal: Set custom limits for this property definition.
    # Warning: saving and updating definitions must always be done via `domain#save_definition`.
    # It already handles providing correct limits.
    # Intended to be used in only in properties framework code.
    sig { params(value: PropertyLimits).void }
    def limits=(value)
      @limits = value
    end

    sig { override.returns(String) }
    def type
      "custom"
    end

    private

    # Internal: Get custom limits for this property definition.
    # We provide a default to ensure backwards compatibility.
    # Limits are injects at the framework level when needed.
    # Do not override this method outside of properties framework code.
    sig { returns(PropertyLimits) }
    def limits
      @limits ||= CustomPropertiesCore::PropertyLimits.new
      T.must(@limits)
    end

    sig { void }
    def ensure_uniq_of_allow_values
      allowed_values.uniq!
    end

    sig { void }
    def value_type_enabled
      return if value_type.nil? # checked in presence validator

      err = CustomPropertiesValidator.validate_definition_value_type(
        definition: self,
        actor_type_enabled: actor_type_enabled?,
      )

      if err
        errors.add(err.field, err.message)
        # Stop further validation to avoid leaking details about gated property types
        throw :abort
      end
    end

    sig { void }
    def validate_allowed_values
      # We do not want to add confusing error messages about allowed values if the value_type is missing.
      # validates_presence_of :value_type will already return an error if value_type is nil
      return if value_type.nil?

      err = CustomPropertiesValidator.validate_definition_allowed_values(
        definition: self,
        limits: limits,
      )
      errors.add(err.field, err.message) if err
    end

    sig { void }
    def validate_default_value_field
      return if value_type.nil? # checked in presence validator

      err = CustomPropertiesValidator.validate_definition_default_value(
        definition: self,
        limits: limits,
      )
      errors.add(err.field, err.message) if err
    end

    sig { void }
    def validate_regex
      return if value_type.nil?

      err = CustomPropertiesValidator.validate_definition_regex(
        definition: self,
      )
      errors.add(err.field, err.message) if err
    end

    sig { void }
    def instrument_create
      instrument :create, create_delete_payload
    end

    sig { void }
    def instrument_destroy
      instrument :destroy, create_delete_payload
    end

    sig { void }
    def instrument_update
      instrument :update, changes_payload if changes_payload
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def event_payload
      owner_hash = business_source_type? ? { business: source } : { org: source }

      {
        definition_id: id,
        property_name: property_name,
      }.merge(owner_hash)
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def create_delete_payload
      {
        description: description,
        value_type: value_type,
        required: required,
        allowed_values: allowed_values,
        default_value: default_value,
      }
    end

    sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    def changes_payload
      payload = {}

      AUDITABLE_FIELDS.each do |field|
        if saved_change_to_attribute?(field)
          if field == :config
            old_config = attribute_before_last_save(field)
            config = send(field) # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod

            old_default_value = old_config&.fetch("default_value")
            default_value = config&.fetch("default_value")
            if old_default_value != default_value
              payload[:old_default_value] = old_default_value
              payload[:default_value] = default_value
            end
          else
            payload["old_#{field}".to_sym] = attribute_before_last_save(field)
            payload["#{field}".to_sym] = send(field) # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
          end
        end
      end

      payload if payload.present?
    end

    # Essentially the same as the method in packages/custom_properties_core/app/public/custom_properties/domain_accessor_base.rb
    def actor_type_enabled?
      if source.is_a?(Organization) && source.business.present?
        FeatureFlag.vexi.enabled?(:custom_properties_actor_type, source.business, default: false)
      else
        FeatureFlag.vexi.enabled?(:custom_properties_actor_type, source, default: false)
      end
    end
  end
end
