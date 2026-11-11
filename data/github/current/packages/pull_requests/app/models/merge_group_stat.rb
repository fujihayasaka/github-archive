# typed: true
# frozen_string_literal: true

class MergeGroupStat < ApplicationRecord::Collab
  belongs_to :queue, class_name: :MergeQueue, foreign_key: :merge_queue_id # rubocop:todo Rails/InverseOf
  include ::Repositories::BelongsToRepository
  belongs_to_repository_via_domain

  validates :merge_queue_id, presence: true
  validates :repository_id, presence: true
  validates :ref, presence: true
  validates :base_branch, presence: true
  validates :first_pr_queued_at, presence: true
  validates :pull_requests_merged_count, presence: true, numericality: { only_integer: true, greater_than: 0 }

  def self.merge_counts_by_day(queue:, base_branch:, start_date:, end_date:)
    where(queue: queue, base_branch: base_branch)
      .where("DATE(created_at) BETWEEN ? AND ?", start_date, end_date)
      .group("DATE(created_at)")
      .sum(:pull_requests_merged_count)
  end
end
