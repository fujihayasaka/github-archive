# typed: true
# frozen_string_literal: true

module RepositoryRulesets
  class PropertyDescriptor
    extend T::Helpers
    abstract!

    sig do
      params(
        property_name: String,
        description: T.nilable(String),
        value_type: String,
        allowed_values: T.nilable(T::Array[String]),
        source: String,
        icon: String,
        display_name: String,
        validator: T.nilable(T.proc.params(value: String, context: T.nilable(RuleEngine::ParameterSchema::ValidationContext)).returns(T::Boolean))
      ).void
    end
    def initialize(property_name:, description:, value_type:, allowed_values:, source:, icon:, display_name:, validator: nil)
      @property_name = property_name
      @description = description
      @value_type = value_type
      @allowed_values = allowed_values
      @source = source
      @icon = icon
      @display_name = display_name
      @validator = validator
    end

    attr_reader :property_name, :description, :value_type, :allowed_values, :source, :icon, :display_name

    sig { params(values: T::Array[String], context: T.nilable(RuleEngine::ParameterSchema::ValidationContext)).returns(T::Boolean) }
    def validate(values, context = nil)
      if @validator
        values.all? { |value| @validator.call(value, context) }
      else
        ruleset_target = context.root["ruleset_target"] unless context.nil?
        return false if %w[single_select multi_select].include?(@value_type) && get_allowed_values(ruleset_target).nil?

        values.all? do |value|
          Repositories.domain.custom_properties.validate_allowed_values(
            property_name: @property_name,
            value_type: @value_type,
            allowed_values: get_allowed_values(ruleset_target),
            value: value
          ).empty?
        end
      end
    end

    sig { params(ruleset_target: T.nilable(String)).returns(T.nilable(T::Array[String])) }
    def get_allowed_values(ruleset_target = nil)
      @allowed_values
    end
  end
end
