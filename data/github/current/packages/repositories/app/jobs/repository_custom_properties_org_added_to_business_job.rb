# typed: strict
# frozen_string_literal: true

# Job that will remove repository custom property definitions from the provided organization that conflict by name
# with definitions in the business. Business-level definitions take precedence over organization-level definitions
# rendering conflicting definitions in the organization obsolete.
#
# This job is used when an existing organization is added to a business
class RepositoryCustomPropertiesOrgAddedToBusinessJob < ApplicationJob
  queue_as :repository_custom_properties_org_added_to_business_job
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  # This job will run when an organization is created. Sometimes replication lag causes the organization to not be
  # found immediately, so we retry to ensure it can find the organization.
  retry_on ActiveRecord::RecordNotFound, wait: :polynomially_longer, attempts: 5

  # We write to Repositories in a connected_to(:writing) block but we declare
  # it as a replica here so we wait for replication lag on this cluster when reading
  use_replicas ApplicationRecord::Repositories,
    ApplicationRecord::Mysql1

  sig { params(business: Business, org: Organization).void }
  def perform(business:, org:)
    biz_props = Repositories.domain.custom_properties.get_own_definitions(business)
    biz_property_names = biz_props.pluck(:property_name).map(&:downcase).to_set
    org_property_names = Repositories.domain.custom_properties.get_own_definitions(org).pluck(:property_name)

    conflicting_property_names = org_property_names.select do |org_property_name|
      biz_property_names.include?(org_property_name.downcase)
    end

    if conflicting_property_names.any?
      with_write do
        conflicting_property_names.each do |name|
          Repositories.domain.custom_properties.delete_definition(org, name, reindex_source_repos: false)
        end
      end
    end

    required_biz_props = biz_props.any?(&:required)
    should_reindex = conflicting_property_names.any? || required_biz_props
    # Org repos need to be reindexed if there were definitions removed or if there are required business definitions
    # in the business that the org was added to.
    BulkReposIndexJob.reindex_org(org.id) if should_reindex
  end
end
