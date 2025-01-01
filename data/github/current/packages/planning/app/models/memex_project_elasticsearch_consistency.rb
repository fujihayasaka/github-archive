# typed: strict
# frozen_string_literal: true

class MemexProjectElasticsearchConsistency < ApplicationRecord::Domain::Memexes
  extend T::Sig
  include Stafftools::SplunkHelper

  self.table_name = "memex_project_elasticsearch_consistency"

  belongs_to :memex_project

  INCONSISTENCY_THRESHOLD = 0.95
  SAMPLE_PERCENTAGE = 0.05

  scope :inconsistent, -> { where("consistency < ?", INCONSISTENCY_THRESHOLD) }
  scope :consistent, -> { where("consistency >= ?", INCONSISTENCY_THRESHOLD) }

  # sorts unevaluated records first, then sorts evaluated records by oldest evaluation date in ascending order
  scope :least_recently_evaluated, -> { order(Arel.sql("evaluated_at IS NOT NULL")).order(evaluated_at: :asc) }

  sig do
    params(
      reconciled_count: Numeric,
      total_count: Numeric,
    )
    .returns(T.nilable(Float))
  end
  def self.consistency_score(reconciled_count:, total_count:)
    return unless total_count.positive?

    (1 - (reconciled_count.to_f / total_count.to_f)).to_f
  end

  sig do
    params(
      memex_project_id: Integer,
      repair_started_at: T.nilable(Time),
      repair_finished_at: T.nilable(Time),
      evaluated_at: T.nilable(Time),
      consistency: T.nilable(Float)
    )
    .returns(MemexProjectElasticsearchConsistency)
  end
  def self.create_or_update(memex_project_id, repair_started_at: nil, repair_finished_at: nil, evaluated_at: nil, consistency: nil)
    consistency_record = self.find_or_initialize_by(memex_project_id: memex_project_id)
    attrs = {
      repair_started_at:,
      repair_finished_at:,
      evaluated_at:,
      consistency: consistency || consistency_record.consistency.to_f
    }.compact
    consistency_record.tap { _1.update!(attrs) }
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
end
