# typed: strict
# frozen_string_literal: true

module CustomProperties
  module IPropertyValue
    extend T::Sig
    extend T::Helpers

    include CustomProperties
    include Kernel

    interface!

    sig { abstract.returns(IPropertyDefinition) }
    def definition; end

    sig { abstract.returns(String) }
    def property_name; end

    # The manually-set value of the property, if any
    # Features integrating with custom properties should be using `effective_value` instead.
    # This value is available for certain scenarios like the custom properties settings pages that need
    # to see if an underlying value is set, or if a default value is being used.
    sig { abstract.returns(T.nilable(PropertyValue)) }
    def manual_value; end

    # The actual value of the property, taking into account the default value if the property is required
    # This is the value that should be used by features integrating with custom properties.
    sig { abstract.returns(T.nilable(PropertyValue)) }
    def effective_value; end
  end
end
