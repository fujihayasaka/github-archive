# typed: strict
# frozen_string_literal: true

module CustomProperties
  module IDefinitionsManager
    extend T::Helpers

    include Kernel

    interface!

    # Read definitions
    #
    # Returns sorted list of definitions
    # If both org and business definitions exist, schema is resolved.
    # Business definitions take precedence over org definitions.
    #
    # If `only_defined_by_source` is true, only definitions defined at current source are returned.
    # WARNING: `only_defined_by_source` is only meant for properties admin purposes.
    # Avoid using it for integrations with properties.
    sig { abstract.params(only_defined_by_source: T::Boolean).returns(T::Array[IPropertyDefinition]) }
    def get_definitions(only_defined_by_source: false); end

    # Get definition by property name
    #
    # Returns the definition model or nil if it does not exist
    # If both org and business definitions exist, schema is resolved.
    # Business definitions take precedence over org definitions.
    sig { abstract.params(property_name: String).returns(T.nilable(IPropertyDefinition)) }
    def get_definition(property_name); end

    # Add or replace the definition of a custom property for the collection's org
    #
    # property_name - Property name to define
    # value_type - Type of the property value. One of ["string", "single_select", "multi_select", "true_false"]. Defaults to "string".
    # required - Whether the property is required or not. Defaults to false.
    # default_value - Default value for the property. Defaults to nil. Must be provided if required is true.
    # description - Description of the property. Defaults to nil.
    # allowed_values - Allowed values for the property. Defaults to nil.
    # values_editable_by - Who can edit the values of the property. One of ["org_actors", "org_and_repo_actors"]. Defaults to "org_actors".
    # regex - Regular expression for validating the property value. Defaults to nil.
    #
    # Returns the definition model
    sig do
      abstract.params(
        property_name: String,
        value_type: String,
        required: T::Boolean,
        default_value: T.nilable(PropertyValue),
        description: T.nilable(String),
        allowed_values: T.nilable(T::Array[String]),
        values_editable_by: T.nilable(String),
        regex: T.nilable(String),
      ).returns(IPropertyDefinition)
    end
    def save_definition(property_name:, value_type: "string", required: false, default_value: nil, description: nil, allowed_values: nil, values_editable_by: "org_actors", regex: nil); end

    # Delete definition
    #
    # property_name - A property_name to remove
    #
    # Returns the deleted definition or nil if it did not exist
    sig { abstract.params(property_name: String).returns(T.nilable(IPropertyDefinition)) }
    def delete_definition(property_name); end

    # Promote a property definition from an organization to the enterprise level.
    #
    # Promotion requires using business level definitions manager.
    # Property can be promoted only if there are no other properties with the same name in the enterprise orgs.
    #
    # definition - Org level property definition to promote
    # Returns promoted property definition
    # Raises a NotImplementedError if the definitions manager was initialized with an org
    sig { abstract.params(definition: IPropertyDefinition).returns(IPropertyDefinition) }
    def promote_definition(definition); end

    # Case insensitive search for definitions with similar name in child orgs
    #
    # Requires using business level definitions manager.
    #
    # Returns a list of definitions.
    # Raises a NotImplementedError if the definitions manager was initialized with an org
    sig { abstract.params(property_name: String).returns(T::Array[DefinitionBase]) }
    def child_orgs_definitions_by_name(property_name); end
  end
end
