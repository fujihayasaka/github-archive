# typed: strict
# frozen_string_literal: true

# Job that will remove repository custom property definitions from the provided organization that conflict by name
# with definitions in the business. Business-level definitions take precedence over organization-level definitions
# rendering conflicting definitions in the organization obsolete.
#
# This job is used when an existing organization is added to a business
class RemoveRepoCustomPropertyDefinitionOrgConflictsJob < ApplicationJob
  queue_as :remove_repo_custom_property_definition_org_conflicts_job
  retry_on_dirty_exit

  sig { params(business: Business, org: Organization).void }
  def perform(business:, org:)
    biz_property_names = Repositories.domain.custom_properties.get_own_definitions(business).pluck(:property_name).map(&:downcase).to_set
    org_property_names = Repositories.domain.custom_properties.get_own_definitions(org).pluck(:property_name)

    conflicting_property_names = org_property_names.select do |org_property_name|
      biz_property_names.include?(org_property_name.downcase)
    end
    return if conflicting_property_names.empty?

    with_write do
      conflicting_property_names.each do |name|
        Repositories.domain.custom_properties.delete_definition(org, name)
      end
    end
  end
end
