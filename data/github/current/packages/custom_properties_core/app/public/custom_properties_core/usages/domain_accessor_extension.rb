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
        track("properties_usage_tracking.get_all_usages_for", tags: config.additional_tracking_tags(source)) do
          definition = find_definition!(source, property_name)
          T.unsafe(config_extension.usage_class).for_definition(definition).to_a
        end
      end

      # Gets all properties used by a given resource
      #
      # resource - the resource to get the property usages for.
      sig { params(resource: IPropertyResource).returns(T::Array[IPropertyDefinition]) }
      def get_all_properties_used_by(resource)
        track("properties_usage_tracking.get_all_properties_used_by", tags: { resource_type: resource.properties_resource_type }) do
          usages_relation = T.unsafe(config_extension.usage_class).for_resource(resource)
          config_extension.definition_class.where(id: usages_relation.select(:definition_id)).to_a
        end
      end

      # Add a new usage of a custom property for a given resource.
      #
      # property_name - Property name being used
      # property_source - The business or organization that the property is defined on
      # resource - The resource the property is being used on
      #
      # Returns the created or existing usage.
      # Raises an error if the property does not exist for the given source.
      sig do
        params(
          property_name: String,
          property_source: PropertySource,
          resource: IPropertyResource
        ).returns(IPropertyUsage)
      end
      def register_property_usage(property_name:, property_source:, resource:)
        track("properties_usage_tracking.register_property_usage", tags: usage_tracking_tags(property_source, resource_type: resource.properties_resource_type)) do
          # Throw if the definition doesn't exist
          definition = find_definition!(property_source, property_name)

          # Note that we can't do any validation on the existence of a resource.
          # We are relying on the consumer to give us correct information, and simply persist
          # it to the usages table.

          config_extension.usage_class.create_or_find_by(
            definition_id: definition.id,
            resource_id: resource.properties_resource_id,
            resource_type: resource.properties_resource_type,
          )
        end
      end

      # Batch updates custom property usages for a list of resources to match the provided
      # list of property names for each.
      # New usages will be created and existing usages will be removed as needed.
      #
      # property_source - The business or organization that the properties are defined on
      # usages - A hash mapping resources to a list of property names that its usages should reflect
      #
      # Raises an error if any of the provided property names do not exist for the given source.
      sig do
        params(
          property_source: PropertySource,
          usages: T::Hash[IPropertyResource, T::Array[String]],
        ).void
      end
      def resolve_property_usages(property_source:, usages:)
        # Since all resources must be of the same type we can extract the type from the first usage to add to our tracking tags.
        first_resource = usages.keys.first
        return unless first_resource # Nothing to resolve if no resources are provided so return early

        track("properties_usage_tracking.resolve_property_usages", tags: usage_tracking_tags(property_source, resource_type: first_resource.properties_resource_type)) do
          to_create_usages_for = T.let({}, T::Hash[IPropertyResource, T::Set[Integer]])
          existing_usages_by_resource = T.let({}, T::Hash[Integer, T::Array[IPropertyUsage]])
          usage_ids_to_remove = T.let([], T::Array[Integer])

          definitions_by_name = definitions_by_name!(property_source, usages)

          config_extension.usage_class.transaction do
            T.unsafe(config_extension.usage_class).for_resources(usages.keys).each do |usage|
              (existing_usages_by_resource[usage.resource_id] ||= []) << usage
            end

            usages.each do |resource, properties|
              existing_usages = existing_usages_by_resource[T.must(resource.properties_resource_id)] || []
              definitions = properties.uniq.map { |name| T.must(definitions_by_name[name.downcase]) }

              existing_definitions = existing_usages.map(&:definition_id).to_set
              desired_definitions = definitions.map(&:id).to_set

              to_create_usages_for[resource] = desired_definitions - existing_definitions

              definitions_to_remove = existing_definitions - desired_definitions
              if definitions_to_remove.any?
                usage_ids_to_remove.concat(
                  existing_usages.filter_map { |u| T.unsafe(u).id if definitions_to_remove.include?(u.definition_id) }
                )
              end
            end

            if usage_ids_to_remove.any?
              # Using delete_all for performance. Switch to destroy_all if model callbacks are added.
              config_extension.usage_class
                .where(id: usage_ids_to_remove)
                .delete_all
            end

            to_create_usages_for.each do |resource, definitions|
              definitions.each do |id|
                config_extension.usage_class.create!(
                  definition_id: id,
                  resource_id: resource.properties_resource_id,
                  resource_type: resource.properties_resource_type,
                )
              end
            end
          end
        end
      end

      # Removes an existing usage of a custom property for a given resource.
      #
      # property_name - Property name being removed
      # property_source - The business or organization that the property is defined on
      # resource - The resource the property is being removed from
      #
      # Returns the removed usage, or nil if it did not exist.
      # Raises an error if the property does not exist for the given source.
      sig do
        params(
          property_name: String,
          property_source: PropertySource,
          resource: IPropertyResource
        ).returns(T.nilable(IPropertyUsage))
      end
      def unregister_property_usage(property_name:, property_source:, resource:)
        track("properties_usage_tracking.unregister_property_usage", tags: usage_tracking_tags(property_source, resource_type: resource.properties_resource_type)) do
          # Throw if the definition doesn't exist
          definition = find_definition!(property_source, property_name)

          usage = config_extension.usage_class.find_by(
            definition_id: definition.id,
            resource_id: resource.properties_resource_id,
            resource_type: resource.properties_resource_type,
          )

          # TODO: log if usages does not exist
          usage.destroy! if usage
        end
      end

      # Removes all existing usages for a given resource.
      #
      # resource - The resource to remove all usages for
      #
      # Returns the removed usages or an empty array if no usages were found.
      sig do
        params(
          resource: IPropertyResource
        ).returns(T::Array[IPropertyUsage])
      end
      def unregister_all_property_usages_for(resource:)
        track("properties_usage_tracking.unregister_all_property_usages_for", tags: { resource_type: resource.properties_resource_type }) do
          relation = config_extension.usage_class
            .where(resource_id: resource.properties_resource_id, resource_type: resource.properties_resource_type)

          removed_usages = relation.to_a
          # Using delete_all for performance. Switch to destroy_all if model callbacks are added.
          relation.delete_all

          removed_usages
        end
      end

      private

      sig { returns(ICustomPropertiesConfigExtension) }
      def config_extension
        cfg = config
        raise NotImplementedError, "Custom properties usages are not supported for this domain" unless cfg.is_a?(ICustomPropertiesConfigExtension)
        cfg
      end

      sig { params(property_source: PropertySource, resource_type: T.nilable(String)).returns(T.nilable(T::Hash[T.any(String, Symbol), String])) }
      def usage_tracking_tags(property_source, resource_type: nil)
        tags = config.additional_tracking_tags(property_source)
        return tags unless resource_type

        (tags || {}).merge(resource_type: resource_type)
      end

      sig { params(source: PropertySource, property_name: String).returns(IPropertyDefinition) }
      def find_definition!(source, property_name)
        definition = definitions_manager(source).get_definition(property_name)
        raise ArgumentError, "Invalid entity: property with name #{property_name} does not exist in the #{source} schema" unless definition

        definition
      end

      sig do
        params(
          source: PropertySource,
          usages: T::Hash[IPropertyResource, T::Array[String]],
        ).returns(T::Hash[String, IPropertyDefinition])
      end
      def definitions_by_name!(source, usages)
        definitions = get_definitions(source)
        definitions_by_name = T.let({}, T::Hash[String, IPropertyDefinition])

        definitions.each do |definition|
          definitions_by_name[definition.property_name.downcase] = definition
        end

        usages.each_value do |property_names|
          property_names.each do |property_name|
            key = property_name.downcase
            next if definitions_by_name.key?(key)

            raise ArgumentError, "Invalid entity: property with name #{property_name} does not exist in the #{source} schema"
          end
        end

        definitions_by_name
      end
    end
  end
end
