# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class CustomPropertyValueInput < Platform::Inputs::Base
      description "The custom property name and value to be set."

      argument :property_name, String, "The name of the custom property.", required: true
      argument :value, Scalars::CustomPropertyValue, "The value to set for the custom property. Using a value of null will unset the property value, reverting to the default value if the property is required.", required: false
    end
  end
end
