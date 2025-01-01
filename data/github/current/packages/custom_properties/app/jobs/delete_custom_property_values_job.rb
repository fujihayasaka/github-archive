# typed: true
# frozen_string_literal: true

# Job that will delete every value row for a given property
# in all the repos for the given org.
#
# It's DANGEROUS, so it should only be used to clean up values
# that are orphan or that are becoming orphan immediately.
#
class DeleteCustomPropertyValuesJob < ApplicationJob
  queue_as :delete_custom_property_values
  retry_on_dirty_exit

  sig { params(org: Organization, definitions: T::Array[CustomProperties::IPropertyDefinition]).void }
  def perform(org:, definitions:)
    definitions_manager = CustomProperties::Public.definitions_manager(org)
    manager = CustomProperties::Public.values_manager(definitions_manager)
    with_write do
      manager.delete_all_values(definitions)
    end
  end
end
