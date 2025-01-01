# typed: strict
# frozen_string_literal: true

class MemexProjectElasticsearchConsistency < ApplicationRecord::Domain::Memexes
  include Stafftools::SplunkHelper

  self.table_name = "memex_project_elasticsearch_consistency"

  belongs_to :memex_project

  INCONSISTENCY_THRESHOLD = 0.95
  SAMPLE_PERCENTAGE = 0.05

  scope :inconsistent, -> { where("consistency < ?", INCONSISTENCY_THRESHOLD) }
  scope :consistent, -> { where("consistency >= ?", INCONSISTENCY_THRESHOLD) }

  # sorts unevaluated records first, then sorts evaluated records by oldest evaluation date in ascending order
  scope :least_recently_evaluated, -> { order(Arel.sql("evaluated_at IS NOT NULL")).order(evaluated_at: :asc) }

  before_validation :set_default_consistency, on: :create

  sig do
    params(
      inconsistent_count: Numeric,
      total_count: Numeric,
    )
    .returns(T.nilable(Float))
  end
  def self.consistency_score(inconsistent_count:, total_count:)
    if total_count.zero?
      if inconsistent_count.zero?
        # A project with no items is considered consistent when the reconciled count is also zero
        return 1.0
      else
        raise ArgumentError, "total_count can only be 0 when inconsistent_count is also 0, inconsistent_count was '#{inconsistent_count}'"
      end
    end

    (1 - (inconsistent_count.to_f / total_count.to_f)).to_f
  end

  # Returns the consistency score for the most recent evaluation limit by `sample_size`
  #  - Use to determine the overall consistency of the index
  #
  sig { returns(Float) }
  def self.recent_consistency_score
    limit = sample_size
    consistent_projects_count = from(
      select(:consistency)
      .order(evaluated_at: :desc)
      .limit(limit)
    ).consistent.count
    consistency_score(inconsistent_count: limit - consistent_projects_count, total_count: limit) || 0.0
  end

  # Returns a sample size of projects to consider for consistency evaluation
  # This is a percentage of the total number of projects in the table
  #  - Primarily used to determine the number of projects to enqueue for resync in `QueueMemexElasticsearchResyncsJob`
  #  - Also used to determine the number of projects to consider for consistency evaluation in
  #     `ReportMemexProjectItemsIndexConsistencyMetricJob`
  #
  sig { returns(Integer) }
  def self.sample_size = (count * SAMPLE_PERCENTAGE).round

  sig { returns(Integer) }
  def percentage = (consistency * 100).round

  sig { returns(T::Boolean) }
  def consistent? = consistency >= INCONSISTENCY_THRESHOLD

  sig { returns(T::Boolean) }
  def inconsistent? = !consistent?

  sig { returns(T.nilable(String)) }
  def splunk_repair_log_url
    latest = evaluated_at.present? ? evaluated_at.to_i : "now"
    earliest = evaluated_at.present? ? (T.must(evaluated_at) - 1.hour).to_i : "-24h@h"

    splunk_url({
      earliest:,
      latest:,
      q: (
        "search " +
        'index="prod-resque" ' +
        "gh.memex.project.id=#{memex_project_id} " +
        'code.namespace="Search::MemexProjectItemReconciler" ' +
        'code.function="reconcile!"'
      ),
    })
  end

  sig { void }
  private def set_default_consistency
    self.consistency = BigDecimal("0") if consistency.nil?
  end
end
