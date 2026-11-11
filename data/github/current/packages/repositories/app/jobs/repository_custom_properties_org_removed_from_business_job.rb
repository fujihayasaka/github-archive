# typed: strict
# frozen_string_literal: true

# Job that will delete every value row for all business property definitions
# in all the repos for the given org.
#
# It's DANGEROUS, so it should only be used to clean up values
# when removing an org from a business.
#
class RepositoryCustomPropertiesOrgRemovedFromBusinessJob < ApplicationJob
  queue_as :repository_custom_properties_org_removed_from_business_job
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  # We write to Repositories in a connected_to(:writing) block but we declare
  # it as a replica here so we wait for replication lag on this cluster when reading
  use_replicas ApplicationRecord::Repositories,
    ApplicationRecord::Mysql1

  # When operating on large numbers of properties, this is the batch size to work on smaller chunks.
  BATCH_SIZE = 1000

  sig { params(business: Business, org: Organization).void }
  def perform(business:, org:)
    repo_ids = org.repositories.ids
    biz_definitions = Repositories.domain.custom_properties.get_own_definitions(business)
    definition_ids = biz_definitions.pluck(:id)
    return if repo_ids.empty? || definition_ids.empty?

    repo_ids.each_slice(BATCH_SIZE) do |ids|
      with_write do
        CustomPropertyValue.for_target_ids(ids).for_definition_ids(definition_ids).delete_all
      end
    end

    GitHub.instrument "org.delete_custom_property_values_for_definition", {
      org: org,
      property_name: biz_definitions.pluck(:property_name)
    }

    BulkReposIndexJob.reindex_org(org.id)
  end
end
