# typed: true
# frozen_string_literal: true

class MergeQueueLockedRef < ApplicationRecord::Collab

  include ::Repositories::BelongsToRepository
  flagged_belongs_to_repository_via_domain required: true
  # rubocop:todo Rails/InverseOf
  belongs_to :queue,
    required: true,
    class_name: :MergeQueue,
    foreign_key: :merge_queue_id
  # rubocop:enable Rails/InverseOf

  validates :ref, presence: true, uniqueness: { scope: [:queue, :repository] }

  sig { params(entry: MergeQueueEntry).returns(MergeQueueLockedRef) }
  def self.create_for!(entry:)
    pr = T.must(entry.pull_request)

    create!(
      repository_id: pr.head_repository_id,
      queue: entry.queue,
      ref: pr.head_ref,
    )
  end

  sig { params(entry: T.nilable(MergeQueueEntry)).returns(T.nilable(MergeQueueLockedRef)) }
  def self.for(entry:)
    return unless pr = entry&.pull_request

    find_by(
      repository_id: pr.head_repository_id,
      queue: entry.queue,
      ref: pr.head_ref,
    )
  end
end
