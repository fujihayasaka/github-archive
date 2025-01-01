# typed: true
# frozen_string_literal: true

class DeleteConflictCustomPropertyDefinitionsJob < ApplicationJob
  queue_as :delete_conflict_custom_property_definitions
  retry_on_dirty_exit

  sig { params(org: Organization, business: Business).void }
  def perform(org:, business:)
    biz_property_names = CustomProperties::Public.business_definitions_manager(business)
      .get_definitions(only_defined_by_source: true)
      .pluck(:property_name)
    biz_property_names.map!(&:downcase)

    org_manager = CustomProperties::Public.definitions_manager(org)
    org_property_names = org_manager.get_definitions(only_defined_by_source: true).pluck(:property_name)

    conflicting_property_names = org_property_names.select do |org_property_name|
      biz_property_names.include?(org_property_name.downcase)
    end
    return if conflicting_property_names.empty?

    with_write do
      conflicting_property_names.each do |name|
        org_manager.delete_definition(name)
      end
    end
  end
end
