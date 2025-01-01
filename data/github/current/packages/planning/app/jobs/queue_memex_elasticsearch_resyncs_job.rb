# typed: true
#
# We would like for this to be `typed: strict`, but we cannot do that until
# https://github.com/github/github/issues/283070 is resolved.

# frozen_string_literal: true

# This job is responsible to enqueue a subset of projects
#  (currently 5% of all records in the `memex_project_elasticsearch_consistency` table)
# for resync based on the following criteria:
#
# 1. Projects that have not yet been evaluated (evaluated_at is nil).
# 2. And, records with the oldest evaluation date in this subset.
#
# The order in which projects are enqueued for resync is determined by `memex_project_elasticsearch_consistency`
#
class QueueMemexElasticsearchResyncsJob < ApplicationJob
  extend T::Sig

  BATCH_SIZE = T.let(1000, Integer)
  SCHEDULING_INTERVAL = T.let(4.hours, ActiveSupport::Duration)
  SAMPLE_SIZE_METRIC_NAME = T.let("gh.memex.memex_project_items.consistency.sample_size", String)

  # We only want a single instance of this job to run at any given time,
  # so provide a lock key that is the same across all instances of the job.
  locked_by timeout: 90.minutes, key: ->(_job) { self.name }

  schedule interval: SCHEDULING_INTERVAL, condition: -> { !GitHub.single_tenant_enterprise? }
  queue_as :queue_memex_elasticsearch_resyncs

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  def perform
    project_ids_in_batches.each do |project_ids|
      MemexProject::ResyncItems.resync_later(project_ids)
    end
  end

  private def project_ids_in_batches
    sample_size = MemexProjectElasticsearchConsistency.sample_size
    GitHub.dogstats.gauge(SAMPLE_SIZE_METRIC_NAME, sample_size)
    MemexProjectElasticsearchConsistency
      .least_recently_evaluated
      .limit(sample_size)
      .pluck(:memex_project_id)
      .each_slice(BATCH_SIZE)
  end
end
