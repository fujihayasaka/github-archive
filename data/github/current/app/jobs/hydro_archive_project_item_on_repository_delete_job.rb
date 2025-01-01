# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class HydroArchiveProjectItemOnRepositoryDeleteJob < Repositories::RepositoryHydroMessageJob
  queue_as :hydro_archive_project_item_on_repository_delete

  # retry_on ExpectedError
  # discard_on IgnoredError

  # Public: process a repository delete Hydro message and
  # archive all memex items related to the repositories issues
  #
  # Returns nothing
  def perform
    # available as instance accessors:
    # - topic: e.g. "octochat.v0.Login"
    # - partition
    # - offset
    # - schema: e.g. "octochat.v0.Login"
    # - kafka_cluster: which cluster this message came from, e.g. "potomac"
    # - message: the message hash, with symbolized keys
    actor = repository.deleted_by || User.ghost
    memex_items = []

    repository.issues.in_batches(of: 500) do |batch|
      GitHub::PrefillAssociations.prefill_associations(batch, :memex_project_items)
      batch.each do |issue|
        memex_items << issue.memex_project_items
      end
    end

    repository.pull_requests.in_batches(of: 500) do |batch|
      GitHub::PrefillAssociations.prefill_associations(batch, :memex_project_items)
      batch.each do |pull|
        memex_items << pull.memex_project_items
      end
    end

    memex_items.flatten.each do |memex_item|
      MemexProjectItem.throttle do
        ActiveRecord::Base.connected_to(role: :writing) do
          memex_item&.archive!(actor)
        end
      end
    end
  end
end
