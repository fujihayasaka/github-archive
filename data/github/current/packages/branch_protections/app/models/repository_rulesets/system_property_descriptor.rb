# typed: true
# frozen_string_literal: true

module RepositoryRulesets
  class SystemPropertyDescriptor < PropertyDescriptor
    extend T::Sig

    sig do
      params(
        property_name: String,
        value_type: String,
        value_accessor: T.proc.params(repository: ::Repository).returns(String),
        icon: String,
        display_name: String,
        allowed_values: T.nilable(T::Array[String]),
        allowed_values_accessor: T.nilable(T.proc.params(ruleset_target: T.nilable(String)).returns(T::Array[String])),
        validator: T.nilable(T.proc.params(value: String, context: T.nilable(RuleEngine::ParameterSchema::ValidationContext)).returns(T::Boolean))
      ).void
    end
    def initialize(property_name:, value_type:, value_accessor:, icon:, display_name:, allowed_values: nil, allowed_values_accessor: nil, validator: nil)
      super(property_name: property_name, description: nil, value_type: value_type, allowed_values:, source: "system", icon: icon, display_name: display_name, validator: validator)
      @value_accessor = value_accessor
      @allowed_values_accessor = allowed_values_accessor
    end

    def value(repository)
      @value_accessor.call(repository)
    end

    sig { override.params(ruleset_target: T.nilable(String)).returns(T.nilable(T::Array[String])) }
    def get_allowed_values(ruleset_target = nil)
      if @allowed_values_accessor.present?
        return @allowed_values_accessor.call(ruleset_target)
      end
      @allowed_values
    end
  end
end
