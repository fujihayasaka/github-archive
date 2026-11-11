# typed: strict
# frozen_string_literal: true

module CustomPropertiesCore
  module Usages
    module DomainAccessorExtension
      extend T::Helpers

      include Kernel

      requires_ancestor { DomainAccessorBase }

      # Gets all usages of a property for a given source and property name
      #
      # source - the source to scope the property definition to.
      # property_name - the name of the property to get the usages for.
      #
      # Raises an error if the property does not exist for the given source.
      sig { params(source: PropertySource, property_name: String).returns(T::Array[IPropertyUsage]) }
      def get_all_usages_for(source, property_name)
        definition = find_definition!(source, property_name)
        T.unsafe(config).usage_class.for_definition(definition).to_a
      end

      # Gets all properties used by a given resource
      #
      # resource_id - the ID of the resource
      # resource_type - the type of the resource
      sig { params(resource_id: Integer, resource_type: T.any(String, Symbol)).returns(T::Array[IPropertyDefinition]) }
      def get_all_properties_used_by(resource_id, resource_type)
        usages_relation = T.unsafe(config).usage_class.for_resource(resource_id, resource_type)
        T.unsafe(config).definition_class.where(id: usages_relation.select(:definition_id)).to_a
      end

      # Add a new usage of a custom property for a given resource.
      #
      # property_name - Property name being used
      # property_source - The business or organization that the property is defined on
      # resource_id - the ID of the resource the property is being used on
      # resource_type - the type of the resource the property is being used on
      #
      # Returns the created or existing usage.
      # Raises an error if the property does not exist for the given source.
      sig do
        params(
          property_name: String,
          property_source: PropertySource,
          resource_id: Integer,
          resource_type: T.any(String, Symbol),
        ).returns(IPropertyUsage)
      end
      def register_property_usage(property_name:, property_source:, resource_id:, resource_type:)
        # Throw if the definition doesn't exist
        definition = find_definition!(property_source, property_name)

        # Note that we can't do any validation on the existence of a resource.
        # We are relying on the consumer to give us correct information, and simply persist
        # it to the usages table.

        T.unsafe(config).usage_class.find_or_create_by(
            definition_id: definition.id,
            resource_id: resource_id,
            resource_type: resource_type.to_s,
          )
      end

      # Removes an existing usage of a custom property for a given resource.
      #
      # property_name - Property name being removed
      # property_source - The business or organization that the property is defined on
      # resource_id - the ID of the resource the property is being removed from
      # resource_type - the type of the resource the property is being removed from
      #
      # Returns the removed usage, or nil if it did not exist.
      # Raises an error if the property does not exist for the given source.
      sig do
        params(
          property_name: String,
          property_source: PropertySource,
          resource_id: Integer,
          resource_type: T.any(String, Symbol),
        ).returns(T.nilable(IPropertyUsage))
      end
      def unregister_property_usage(property_name:, property_source:, resource_id:, resource_type:)
        # Throw if the definition doesn't exist
        definition = find_definition!(property_source, property_name)

        usage = T.unsafe(config).usage_class.find_by(
          definition_id: definition.id,
          resource_id: resource_id,
          resource_type: resource_type.to_s,
        )

        # TODO: log if usages does not exist
        usage.destroy! if usage
      end

      # Removes all existing usages for a given resource.
      #
      # resource_id - the ID of the resource to remove all usages for
      # resource_type - the type of the resource to remove all usages for
      #
      # Returns the removed usages or an empty array if no usages were found.
      sig do
        params(
          resource_id: Integer,
          resource_type: T.any(String, Symbol),
        ).returns(T::Array[IPropertyUsage])
      end
      def unregister_all_property_usages_for(resource_id:, resource_type:)
        removed_usages = T.let([], T::Array[IPropertyUsage])

        T.unsafe(config).usage_class
          .where(resource_id: resource_id, resource_type: resource_type.to_s)
          .in_batches(of: DomainAccessorBase::DESTROY_BATCH_SIZE) do |batch|
            removed_usages.concat(T.cast(batch.destroy_all, T::Array[IPropertyUsage]))
          end

        removed_usages
      end

      private

      sig { params(source: PropertySource, property_name: String).returns(IPropertyDefinition) }
      def find_definition!(source, property_name)
        definition = definitions_manager(source).get_definition(property_name)
        raise ArgumentError, "Invalid entity: property with name #{property_name} does not exist in the #{source} schema" unless definition

        definition
      end
    end
  end
end
