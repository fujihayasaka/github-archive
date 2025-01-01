# typed: true
# frozen_string_literal: true

class MergeQueueEntryStat < ApplicationRecord::Collab
  belongs_to :queue,
    class_name: :MergeQueue,
    foreign_key: :merge_queue_id,
    inverse_of: :entry_stats,
    required: true
  belongs_to :entry,
    class_name: :MergeQueueEntry,
    foreign_key: :merge_queue_entry_id,
    inverse_of: :stat,
    required: true

  validates :enqueued_at, presence: true
  validates :enqueued_in_position, presence: true
end
