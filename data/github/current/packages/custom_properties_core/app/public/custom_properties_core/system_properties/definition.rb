# typed: strict
# frozen_string_literal: true

module CustomPropertiesCore
  module SystemProperties
    class Definition
      include IPropertyDefinition

      ###
      # Definition class for system properties.
      # This class is used to define the available system properties for a domain, including their name,
      # description, value type, and allowed values. This is used for validation and to provide metadata about
      # the system properties.
      #
      # @param property_name the name of the system property
      # @param value_type the type of the system property value. Supported types are "string",
      #   "single_select", "true_false", "multi_select", and "url"
      # @param description an optional description of the system property
      # @param allowed_values an optional array of allowed values for the system property. Required for
      #   "single_select" and "multi_select" value types.
      sig do
        params(
          config: ICustomPropertiesConfig,
          property_name: String,
          value_type: String,
          description: T.nilable(String),
          allowed_values: T.nilable(T::Array[String]),
          required: T::Boolean,
          default_value: T.nilable(PropertyValue),
          regex: T.nilable(String),
        ).void
      end
      def initialize(config:, property_name:, value_type:, description: nil, allowed_values: nil, required: false, default_value: nil, regex: nil)
        @id = T.let(get_definition_id!(config, property_name), Integer)
        @property_name = property_name
        @description = description
        @value_type = value_type
        @allowed_values = allowed_values
        @required = required
        @default_value = default_value
        @regex = regex
        validate!
      end

      sig { override.returns(Integer) }
      attr_reader :id

      sig { override.returns(String) }
      attr_reader :property_name

      sig { override.returns(T.nilable(String)) }
      attr_reader :description

      sig { override.returns(String) }
      attr_reader :value_type

      sig { override.returns(T.nilable(T::Array[String])) }
      attr_reader :allowed_values

      sig { override.returns(T.nilable(String)) }
      attr_reader :regex

      sig { override.returns(T::Boolean) }
      attr_reader :required

      sig { override.returns(T.nilable(PropertyValue)) }
      attr_reader :default_value

      sig { override.returns(T::Boolean) }
      def true_false_value_type?
        value_type == "true_false"
      end

      sig { override.returns(T::Boolean) }
      def string_value_type?
        value_type == "string"
      end

      sig { override.returns(T::Boolean) }
      def single_select_value_type?
        value_type == "single_select"
      end

      sig { override.returns(T::Boolean) }
      def multi_select_value_type?
        value_type == "multi_select"
      end

      sig { override.returns(T::Boolean) }
      def url_value_type?
        value_type == "url"
      end

      sig { override.returns(T::Boolean) }
      def actor_value_type?
        value_type == "actor"
      end

      sig { override.returns(String) }
      def type
        "system"
      end

      # Not implemented methods from the IPropertyDefinition interface.
      # These are not relevant for system properties, but must be defined to satisfy the interface.

      sig { override.returns(String) }
      def values_editable_by
        raise NotImplementedError, "System properties don't support 'values_editable_by' attribute"
      end

      sig { override.returns(Integer) }
      def source_id
        raise NotImplementedError, "System properties don't support 'source_id' attribute"
      end

      sig { override.returns(String) }
      def source_type
        raise NotImplementedError, "System properties don't support 'source_type' attribute"
      end

      sig { override.returns(T::Boolean) }
      def business_source_type?
        raise NotImplementedError, "System properties don't support 'business_source_type?' attribute"
      end

      sig { override.returns(T::Boolean) }
      def org_source_type?
        raise NotImplementedError, "System properties don't support 'org_source_type?' attribute"
      end

      sig { override.returns(IPropertySource) }
      def source
        raise NotImplementedError, "System properties don't support 'source' attribute"
      end

      private

      sig { params(config: ICustomPropertiesConfig, property_name: String).returns(Integer) }
      def get_definition_id!(config, property_name)
        raise NotImplementedError, "System properties are not supported for this domain" unless config.is_a?(ICustomPropertiesConfigExtension)
        system_value_class = config.system_value_class

        definition_id = T.unsafe(system_value_class).definition_ids[property_name]
        raise ArgumentError, "Invalid system property name: #{property_name}" if definition_id.nil?

        definition_id
      end

      sig { void }
      def validate!
        validate_value_type!
        validate_regex!
        validate_allowed_values!
        validate_default_value_field!
      end

      sig { void }
      def validate_regex!
        err = CustomPropertiesValidator.validate_definition_regex(definition: self)
        raise ArgumentError, "#{err.field} #{err.message}" if err
      end

      sig { void }
      def validate_default_value_field!
        err = CustomPropertiesValidator.validate_definition_default_value(
          definition: self,
          limits: CustomPropertiesValidator.system_property_limits,
        )
        raise ArgumentError, "#{err.field} #{err.message}" if err
      end

      sig { void }
      def validate_value_type!
        err = CustomPropertiesValidator.validate_definition_value_type(definition: self)
        raise ArgumentError, "#{err.field} #{err.message}" if err
      end

      sig { void }
      def validate_allowed_values!
        err = CustomPropertiesValidator.validate_definition_allowed_values(
          definition: self,
          limits: CustomPropertiesValidator.system_property_limits,
        )
        raise ArgumentError, "#{err.field} #{err.message}" if err
      end
    end
  end
end
