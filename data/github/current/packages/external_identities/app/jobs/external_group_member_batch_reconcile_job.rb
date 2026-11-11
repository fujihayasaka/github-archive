# typed: true
# frozen_string_literal: true

# Public: Fan-out wrapper around ExternalGroupMemberReconcileJob.
#
# The synchronous SCIM enterprise-groups PUT/PATCH handlers enqueue
# one ExternalGroupMemberReconcileJob per identity from the request thread.
# For groups with thousands of members this adds unnecessary latency
#
# This job moves that call off the request thread and enqueues the reconcile job
# in a background worker instead
class ExternalGroupMemberBatchReconcileJob < ApplicationJob
  queue_as :external_group_member_reconcile

  BATCH_SIZE = 500
  METRICS_PREFIX = "external_identities.external_group_member_batch_reconcile_job"

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  resolve_tenant_context do |args|
    external_group = ExternalGroup.find_by(id: args[:external_group_id])
    external_group&.provider&.business
  end

  # A discarded batch strands every identity in its slice, so record the loss
  # and report it instead of failing silently.
  after_discard do |job, error|
    args = job.arguments.first || {}
    stranded = Array(args[:identity_ids]).uniq.size
    tags = ["operation:#{args[:operation]}", "caller:#{args[:caller]}"]
    GitHub.dogstats.increment("#{METRICS_PREFIX}.dropped", tags: tags)
    GitHub.dogstats.count("#{METRICS_PREFIX}.dropped_identities", stranded, tags: tags)
    GitHub.logger.error(
      "error.message" => "external_group_member_batch_reconcile_job discarded after retries",
      "error.exception" => error,
      "code.namespace" => job.class.name,
      "gh.external_group.id" => args[:external_group_id],
      "gh.identity_count" => stranded,
      "gh.operation" => args[:operation],
      "gh.caller" => args[:caller],
    )
    Failbot.report(error)
  end

  # Public: Fan out per-identity ExternalGroupMemberReconcileJob enqueues.
  #
  # external_group_id - id of the ExternalGroup whose membership changed.
  # identity_ids      - Array of ExternalIdentity ids to reconcile against
  #                     the group. Each id results in one per-identity job.
  # operation         - :add_member or :remove_member; forwarded as the
  #                     `operation` argument to ExternalGroupMemberReconcileJob.
  # caller            - String identifying the call site for telemetry.
  #
  # Returns nothing.
  def perform(external_group_id:, identity_ids:, operation:, caller:)
    return if external_group_id.nil?
    return if identity_ids.blank?

    identity_ids = identity_ids.uniq
    tags = ["operation:#{operation}", "caller:#{caller}"]
    GitHub.dogstats.increment("#{METRICS_PREFIX}.started", tags: tags)
    GitHub.dogstats.distribution("#{METRICS_PREFIX}.identity_count", identity_ids.size, tags: tags, set_default_host_tag: true)

    GitHub.logger.info(
      "info.message" => "Starting external_group_member_batch_reconcile_job",
      "code.namespace" => self.class.name,
      "code.function" => "perform",
      "gh.external_group.id" => external_group_id,
      "gh.identity_count" => identity_ids.size,
      "gh.operation" => operation,
      "gh.caller" => caller,
    )

    identity_ids.each do |identity_id|
      ExternalGroupMemberReconcileJob.perform_later(
        external_identity_id: identity_id,
        external_group_id: external_group_id,
        caller: caller,
        operation: operation,
      )
    end

    # Children enqueued in this run; compare against the call site's
    # `.requested{path:async}` to detect identities stranded by dropped batches.
    GitHub.dogstats.count("#{METRICS_PREFIX}.enqueued", identity_ids.size, tags: tags)
    GitHub.dogstats.increment("#{METRICS_PREFIX}.completed", tags: tags)

    GitHub.logger.info(
      "info.message" => "Finished external_group_member_batch_reconcile_job",
      "code.namespace" => self.class.name,
      "code.function" => "perform",
      "gh.external_group.id" => external_group_id,
      "gh.identity_count" => identity_ids.size,
      "gh.operation" => operation,
      "gh.caller" => caller,
    )
  end
end
