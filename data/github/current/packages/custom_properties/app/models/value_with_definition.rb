# typed: strict
# frozen_string_literal: true

# This wrapper class can be used to return an implementation of 'CustomProperties::IPropertyValue` that avoids round
# trips to the database and N+1s when accessing fields on the definition or value models. There are two main use cases:
#
# 1. When a method queries `CustomPropertyDefinition`s prior to querying associated `CustomPropertyValue`s from the
#   database, initialize with the fetched `CustomPropertyDefinition` and `CustomPropertyValue` objects.
#
# 2. When the property value is nil or not present in the database, initialize with the `CustomPropertyDefinition`
#   and a `nil` value and this wrapper acts as a helper.
class ValueWithDefinition
  include CustomProperties::IPropertyValue
  include CustomProperties
  extend T::Sig

  # The manually-set value of the property, if any
  # Features integrating with custom properties should be using `effective_value` instead.
  # This value is available for certain scenarios like the custom properties settings pages that need
  # to see if an underlying value is set, or if a default value is being used.
  sig { override.returns(T.nilable(PropertyValue)) }
  attr_reader :manual_value

  # The actual value of the property, taking into account the default value if the property is required
  # This is the value that should be used by features integrating with custom properties.
  sig { override.returns(T.nilable(PropertyValue)) }
  attr_reader :effective_value

  # The property definition
  sig { override.returns(CustomProperties::IPropertyDefinition) }
  attr_reader :definition

  sig { override.returns(String) }
  def property_name
    definition.property_name
  end

  # Useful when a method has already fetched the `CustomPropertyDefinition` from the database before querying
  # the associated `CustomPropertyValue`. If there is no `CustomPropertyValue` defined, initialize
  # value as `nil` and use this as helper methods to sort out manual and effective values.
  sig { params(definition: CustomPropertyDefinition, values: T::Array[CustomPropertyValue]).void }
  def initialize(definition, values)
    manual_value = if definition.multi_select_value_type?
      values.empty? ? nil : values.pluck(:value)
    else
      values.first&.value
    end
    @manual_value = T.let(manual_value, T.nilable(PropertyValue))

    effective = if @manual_value
      @manual_value
    elsif definition.required? && definition.default_value
      definition.default_value
    else
      nil
    end

    @effective_value = T.let(effective, T.nilable(PropertyValue))

    @definition = T.let(definition, CustomProperties::IPropertyDefinition)
  end

  sig { params(other: ValueWithDefinition).returns(T::Boolean) }
  def ==(other)
    self.manual_value == other.manual_value &&
    self.effective_value == other.effective_value &&
    self.definition.id == other.definition.id
  end
end
