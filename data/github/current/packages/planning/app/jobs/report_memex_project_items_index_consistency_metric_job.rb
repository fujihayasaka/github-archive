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

    return GitHub.logger.info(
      "Could not compute meaningful value for consistency metric because total number of projects considered was zero",
      "code.namespace" => self.class.name,
      "code.function" => "perform"
    ) if sample_size.zero?

    primary_index = T.must(Elastomer::Indexes::MemexProjectItems.build(name: :PRIMARY))

    # report:
    # - the consistency score for the most recent evaluation limit by `sample_size`
    # - the oldest evaluation date in this subset
    # - the total number of projects considered, the `sample_size`
    consistency_score = MemexProjectElasticsearchConsistency.recent_consistency_score(index_name: primary_index.name) * 100

    tags = ["index:#{primary_index.name}"]
    GitHub.dogstats.gauge(CONSISTENCY_METRIC_NAME, consistency_score.round, tags:)
    GitHub.dogstats.gauge(SAMPLE_SIZE_METRIC_NAME, sample_size, tags:)
    GitHub.dogstats.gauge(OLDEST_EVALUATION_METRIC_NAME, oldest_evaluation_considered, tags:)
  end

  sig { returns(Integer) }
  memoize private def oldest_evaluation_considered
    oldest_record = MemexProjectElasticsearchConsistency
      .least_recently_evaluated
      .limit(1)
      .pluck(:evaluated_at)
      .first
    oldest_record.to_i
  end
end
