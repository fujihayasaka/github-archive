# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

require "audit"

class AuditLogCuratorJob < ApplicationJob
  # start a schedule that will peridoically drop old audit_log indices
  # This should only be run when in GHES

  schedule interval: 12.hours, condition: -> { GitHub.audit_log_es_curator_enabled? }

  # Don't run more than one of this job at a time
  locked_by timeout: 1.hour, key: DEFAULT_LOCK_PROC
  queue_as :audit_logs
  retry_on_dirty_exit

  attr_reader :indexes_to_drop, :indexes_to_keep

  # Dependency injection convenience function for testing
  def es_adapter
    Audit::Elastic::Adapter.new
  end

  def perform
    return if !GitHub.audit_log_es_curator_enabled?

    retention_months = AuditLogSettings.retention_months.value.to_i

    # minumum retention is 3 months. If a user sets retention to less than this value,
    # we'll consider it as infinite retention and this job will be a no-op.
    return if retention_months.nil? || retention_months <= 2

    @indexes_to_keep = []
    # Generate index names for the last number of months that we want to keep
    # If this is set to the default of 3 then we'll have something like
    # ["audit_log-2021-03", "audit_log-2021-02", "audit_log-2021-01"]
    # If we were running this in 2021-03
    es_adapter.generate_index(retention_months).split(",").each do |i|
      # generate_index only returns an alias, we'll need to find
      # the index that the alias is associated with.
      # e.g the index would be in the format "audit_log-1-2021-03-1"
      # which contains the index_name, index_version, slice-name, slice-version.
      idx = es_adapter.get_cluster_index_for_alias(i)
      if !idx.nil?
        @indexes_to_keep << idx
      end
    end

    @indexes_to_keep = @indexes_to_keep.flatten.uniq

    # get all known indices that's currently configured
    # This should return a list of audit log indices that match the format
    # "audit_log-1-2021-03-1"
    all_audit_log_indices = es_adapter.get_cluster_all_audit_log_indices

    # we'll drop indices that are not part of the current retention months list from
    # the above call.
    @indexes_to_drop = all_audit_log_indices - @indexes_to_keep
    GitHub.logger.info(
      "Dropping indices",
      "gh.audit_log.dropped_indices" => @indexes_to_drop,
      "gh.audit_log.indices_retention_months" => retention_months,
      "gh.audit_log.retained_indices" => @indexes_to_keep)
    @indexes_to_drop.each do |idx|
      with_write do
        Elastomer::SearchIndexManager.delete_index(name: idx, index_class: Elastomer::Indexes::AuditLog, force: true)
      end
    end
    # return the current configured auditlog indices
    es_adapter.get_cluster_all_audit_log_indices
  end
end
