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
        belongs_to :definition, class_name: self.definition_class_name, foreign_key: "definition_id", inverse_of: :custom_property_usages

        validates :definition_id, uniqueness: { scope: [:resource_type, :resource_id] }
        validates_presence_of :resource_id
        validates_presence_of :resource_type

        # Gets the property usages for a given definition
        #
        # definition - the definition to get the usages for
        scope :for_definition, ->(definition) { where(definition_id: definition.id) }

        # Gets the property usages for a given resource
        #
        # resource_id - the ID of the resource
        # resource_type - the type of the resource
        scope :for_resource, ->(resource_id, resource_type) { where(resource_id:, resource_type:) }
      end
    end
  end
end
