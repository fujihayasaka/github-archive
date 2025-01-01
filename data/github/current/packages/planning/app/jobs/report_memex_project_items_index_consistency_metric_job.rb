# typed: true
#
# We would like for this to be `typed: strict`, but we cannot do that until
# https://github.com/github/github/issues/283070 is resolved.

# frozen_string_literal: true

# This job computes the consistency score for a subset of projects
#  (currently 5% of all records in the `memex_project_elasticsearch_consistency` table)
# That score reported to Datadog as gauge value under the `CONSISTENCY_METRIC_NAME` key.
#
class ReportMemexProjectItemsIndexConsistencyMetricJob < ApplicationJob
  extend T::Sig
  include GitHub::Memoizer

  SCHEDULING_INTERVAL = T.let(4.hours, ActiveSupport::Duration)

  CONSISTENCY_METRIC_NAME = T.let("gh.memex.memex_project_items.consistency", String)
  OLDEST_EVALUATION_METRIC_NAME = T.let("gh.memex.memex_project_items.consistency.oldest_evaluation", String)
  SAMPLE_SIZE_METRIC_NAME = T.let("gh.memex.memex_project_items.consistency.report.sample_size", String)

  # We only want a single instance of this job to run at any given time,
  # so provide a lock key that is the same across all instances of the job.
  locked_by timeout: 90.minutes, key: ->(_job) { self.name }

  schedule interval: SCHEDULING_INTERVAL, condition: -> { !GitHub.single_tenant_enterprise? }
  queue_as :report_memex_project_items_index_consistency_metric

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  sig { void }
  def perform
    sample_size = MemexProjectElasticsearchConsistency.sample_size

    if sample_size > 0
      consistent_projects_count = MemexProjectElasticsearchConsistency.from(
        MemexProjectElasticsearchConsistency
          .select(:consistency)
          .order(evaluated_at: :desc)
          .limit(sample_size)
      ).consistent.count
      consistency_score = MemexProjectElasticsearchConsistency
        .consistency_score(reconciled_count: sample_size - consistent_projects_count, total_count: sample_size) || 0
      GitHub.dogstats.gauge(CONSISTENCY_METRIC_NAME, (consistency_score * 100).round)
    else
      GitHub.logger.info(
        "Could not compute meaningful value for consistency metric because total number of projects considered was zero",
        "code.namespace" => self.class.name,
        "code.function" => "perform"
      )
    end

    GitHub.dogstats.gauge(SAMPLE_SIZE_METRIC_NAME, sample_size)
    GitHub.dogstats.gauge(OLDEST_EVALUATION_METRIC_NAME, oldest_evaluation_considered) if oldest_evaluation_considered.present?
  end

  sig { returns(T.nilable(Integer)) }
  memoize private def oldest_evaluation_considered
    oldest_record = MemexProjectElasticsearchConsistency
      .least_recently_evaluated
      .limit(1)
      .pluck(:evaluated_at)
      .first
    oldest_record.to_i
  end
end
