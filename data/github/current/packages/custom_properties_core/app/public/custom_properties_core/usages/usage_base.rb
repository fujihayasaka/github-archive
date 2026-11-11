# typed: false # rubocop:disable Sorbet/StrictSigil
# frozen_string_literal: true

# Sorbet does not handle ActiveSupport::Concern well, so we need to disable strictness here

module CustomPropertiesCore
  module Usages
    module UsageBase
      extend ActiveSupport::Concern
      extend T::Helpers

      include IPropertyUsage

      abstract!

      included do
        belongs_to :definition, class_name: self.definition_class_name, foreign_key: :definition_id, inverse_of: :custom_property_usages

        validates_presence_of :resource_id
        validates_presence_of :resource_type
        validates_presence_of :definition_id

        validates :definition_id, uniqueness: { scope: [:resource_type, :resource_id] }

        # Gets the property usages for a given definition
        #
        # definition - the definition to get the usages for
        scope :for_definition, ->(definition) { where(definition_id: definition.id) }

        # Gets the property usages for a given resource
        #
        # resource - the resource to get the usages for
        scope :for_resource, ->(resource) do
          where(
            resource_id: resource.properties_resource_id,
            resource_type: resource.properties_resource_type,
          )
        end

        # Gets the property usages for a set of resources.
        #
        # All resources must be of the same type. Raises ArgumentError if resources have mixed types.
        #
        # resources - the resources to get the usages for
        scope :for_resources, ->(resources) do
          return none if resources.empty?

          # Ensure all resources have the same type
          resource_types = resources.map(&:properties_resource_type).uniq
          if resource_types.size > 1
            raise ArgumentError, "All resources must be of the same type"
          end

          resource_type = resource_types.first
          resource_ids = resources.map(&:properties_resource_id).uniq

          where(resource_type:, resource_id: resource_ids)
        end
      end
    end
  end
end
