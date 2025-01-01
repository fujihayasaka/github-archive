# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true


class HydroUnarchiveProjectItemOnRepositoryRestoreJob < Repositories::RepositoryHydroMessageJob
  queue_as :hydro_unarchive_project_item_on_repository_restore

  # retry_on ExpectedError
  # discard_on IgnoredError

  # Public: process a repository restore Hydro message and
  # unarchive all memex items related to the repositories issues
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

    return if FeatureFlag.vexi.enabled?(:memex_unarchive_on_repository_restore_kill_switch, default: false)
    return unless message[:deleted_at].present?

    deleted_at = Time.at(message[:deleted_at][:seconds], message[:deleted_at][:nanos], :nsec).utc
    memex_items = []
    repository.issues.in_batches(of: 500) do |batch| # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      GitHub::PrefillAssociations.prefill_associations(batch, :memex_project_items) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      batch.each do |issue|
        memex_items << get_eligible_items(issue.memex_project_items, deleted_at)
      end
    end

    repository.pull_requests.in_batches(of: 500) do |batch|
      GitHub::PrefillAssociations.prefill_associations(batch, :memex_project_items)
      batch.each do |pull|
        memex_items << get_eligible_items(pull.memex_project_items, deleted_at)
      end
    end

    memex_items.flatten.each do |memex_item|
      MemexProjectItem.throttle do
        ActiveRecord::Base.connected_to(role: :writing) do
          memex_item&.unarchive!
        end
      end
    end
  end

  private def get_eligible_items(memex_project_items, deleted_at)
    memex_items = []
    return memex_items if memex_project_items.nil?

    memex_project_items.each do |memex_item|
      if memex_item.archived? && deleted_at < memex_item.archived_at.utc
        memex_items << memex_item
      end
    end
    memex_items
  end
end
