# typed: false # rubocop:disable Sorbet/StrictSigil
# frozen_string_literal: true

# Sorbet does not handle ActiveSupport::Concern well, so we need to disable strictness here

module CustomProperties
  module DefinitionBase
    extend ActiveSupport::Concern
    extend T::Helpers
    include GitHub::Memoizer
    include Instrumentation::Model
    include IPropertyDefinition
    # Remove this when the module is changed to CustomPropertiesCore
    include CustomPropertiesCore

    abstract!

    sig { abstract.returns(T::Boolean) }
    def required?; end

    sig { abstract.returns(DefinitionBase) }
    def destroy!; end

    sig { abstract.returns(T::Boolean) }
    def present?; end

    sig { abstract.params(attributes: T.untyped).returns(DefinitionBase) }
    def update!(attributes); end

    ALLOWED_VALUES_SIZE_LIMIT = 200

    AUDITABLE_FIELDS = T.let(%i[allowed_values config required value_type values_editable_by].freeze, T::Array[Symbol])

    included do
      # rubocop:todo GitHub/AvoidActiveRecordCallbacks
      before_save :ensure_uniq_of_allow_values, if: -> { self.allowed_values? }
      # rubocop:enable GitHub/AvoidActiveRecordCallbacks

      has_many :custom_property_values, class_name: self.value_class_name, foreign_key: "definition_id", dependent: :delete_all, inverse_of: :definition

      after_create_commit :instrument_create # rubocop:todo GitHub/AvoidActiveRecordCallbacks
      after_update_commit :instrument_update, if: :saved_changes? # rubocop:todo GitHub/AvoidActiveRecordCallbacks

      # NOTE: Moving the instrument_destroy to commit callback causes a test failure in
      # packages/orgs/test/models/organization/delete_test.rb in enterprise mode,
      # related to the Organization being deleted once this callback in invoked
      # rubocop:todo GitHub/AvoidActiveRecordCallbacks
      after_destroy :instrument_destroy # rubocop:disable GitHub/AfterCommitCallbackInstrumentation
      # rubocop:enable GitHub/AvoidActiveRecordCallbacks

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
      validates_length_of :property_name, minimum: 1, maximum: Public::MAX_LENGTH
      validates :description, length: {
        maximum: Public::DESCRIPTION_MAX_LENGTH,
        too_long: "must be at most %{count} characters"
      }, allow_nil: true
      validates_presence_of :value_type
      validate :value_type_enabled
      validates_presence_of :values_editable_by
      validate :validate_allowed_values
      validate :validate_default_value_type
      validate :validate_default_value
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

    private

    sig { void }
    def ensure_uniq_of_allow_values
      allowed_values.uniq!
    end

    sig { void }
    def value_type_enabled
      return if value_type.nil? # checked in presence validator

      supported_types = %w[string single_select true_false multi_select]
      supported_types << "url" if url_type_enabled?
      supported_types << "actor" if actor_type_enabled?

      unless supported_types.include?(value_type)
        errors.add(:value_type, "has unsupported value '#{value_type}'")
        # Stop further validation to avoid leaking details about gated property types
        throw :abort
      end
    end

    sig { void }
    def validate_allowed_values
      # We do not want to add confusing error messages about allowed values if the value_type is missing.
      # validates_presence_of :value_type will already return an error if value_type is nil
      return if value_type.nil?

      if single_select_value_type? || multi_select_value_type?
        return errors.add(:allowed_values, "must be present if value_type is #{value_type}") if allowed_values.nil?

        unless allowed_values.is_a?(Array)
          return errors.add(:allowed_values, "must be an array of strings")
        end

        if allowed_values.empty?
          return errors.add(:allowed_values, "must contain at least one value")
        elsif allowed_values.size > ALLOWED_VALUES_SIZE_LIMIT
          return errors.add(:allowed_values, "must be maximum #{ALLOWED_VALUES_SIZE_LIMIT} values")
        end

        allowed_values.uniq.each do |value|
          unless value.is_a?(String)
            errors.add(:allowed_values, "'#{value}' must be a string")
            break
          end

          unless value.length <= Public::MAX_LENGTH
            errors.add(:allowed_values, "'#{value}' must be at most #{Public::MAX_LENGTH} characters")
            break
          end

          invalid_chars = CustomPropertiesValidator.value_invalid_chars(value)
          unless invalid_chars.empty?
            errors.add(:allowed_values, "'#{value}' contains invalid characters: #{invalid_chars}")
            break
          end
        end

        counts = {}
        allowed_values.each do |value|
          normalized_value = value.is_a?(String) ? value.strip.downcase : value
          counts[normalized_value] ||= []
          counts[normalized_value] << value

          dupes = counts.filter { |_, v| v.count > 1 }.values.map { |dupes_array| dupes_array.first }
          errors.add(:allowed_values, "contains duplicates: #{dupes.join}") if dupes.size > 0
        end
      else
        errors.add(:allowed_values, "must be nil if value_type is #{value_type}") if allowed_values.present?
      end
    end

    sig { void }
    def validate_default_value_type
      return unless required?
      return errors.add(:default_value, "must be present") unless default_value.present?
      if multi_select_value_type?
        is_valid = default_value.is_a?(Array) && Array(default_value).all? { |v| v.is_a?(String) }
        errors.add(:default_value, "must be an array of strings for 'multi_select' property") unless is_valid
      else
        is_valid = default_value.is_a?(String)
        errors.add(:default_value, "must be a string for '#{value_type}' property") unless is_valid
      end
    end

    sig { void }
    def validate_default_value
      if required?
        if single_select_value_type? || multi_select_value_type?
          invalid_values = Array(default_value) - Array(allowed_values)
          return errors.add(:default_value, "must be part of the allowed values") if invalid_values.present?
        end

        if url_value_type?
          err = CustomPropertiesValidator.invalid_url?(default_value)
          return errors.add(:default_value, err) if err
        end

        regex_pattern = regex
        regex_default_value = default_value # For Sorbet

        if regex_pattern && regex_default_value.is_a?(String)
          errors.add(:default_value, "must match regular expression #{regex_pattern}") unless regex_validator.matches?(regex_default_value, regex_pattern)
        end
      else
        errors.add(:default_value, "must be empty") if default_value.present?
      end
    end

    sig { void }
    def validate_regex
      regex_pattern = regex
      if regex_pattern
        if string_value_type?
          errors.add(:regex, "must be a valid regex pattern") unless regex_validator.is_valid?(regex_pattern)
        else
          errors.add(:regex, "is only supported on string properties")
        end
      end
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

    sig { returns(Regex::RE2Helper) }
    memoize def regex_validator
      Regex::RE2Helper.new
    end

    # Almost exactly the same as in packages/custom_properties/app/public/custom_properties/domain_accessor_base.rb, but
    # I can't reference that without packwerk being unhappy
    def url_type_enabled?
      if source.is_a?(Organization) && source.business.present?
        FeatureFlag.vexi.enabled?(:custom_properties_url_type, source.business, default: false)
      else
        FeatureFlag.vexi.enabled?(:custom_properties_url_type, source, default: false)
      end
    end

    # Essentially the same as the method in packages/custom_properties/app/public/custom_properties/domain_accessor_base.rb
    def actor_type_enabled?
      if source.is_a?(Organization) && source.business.present?
        FeatureFlag.vexi.enabled?(:custom_properties_actor_type, source.business, default: false)
      else
        FeatureFlag.vexi.enabled?(:custom_properties_actor_type, source, default: false)
      end
    end
  end
end
