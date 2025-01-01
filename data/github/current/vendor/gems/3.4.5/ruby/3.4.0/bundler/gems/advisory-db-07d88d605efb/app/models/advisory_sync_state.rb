# frozen_string_literal: true

class AdvisorySyncState < ApplicationRecord
  LIMIT = 25_000
  BATCH_SIZE = 1000

  belongs_to :advisory

  scope :stale, -> { where.not(processed_at: nil).order(:processed_at).limit(LIMIT) }
  scope :unprocessed, -> { where(processed_at: nil).order(:updated_at) }

  def self.batched_advisory_ids_to_sync(scope: :unprocessed)
    syncs = case scope
            when :unprocessed
              AdvisorySyncState.unprocessed
            when :stale
              AdvisorySyncState.stale
            else
              AdvisorySyncState.none
            end

    syncs.limit(LIMIT).pluck(:advisory_id).each_slice(BATCH_SIZE)
  end

  def self.enqueue(advisory)
    state = advisory.sync_state || advisory.build_sync_state
    state.processed_at = nil
    state.pushed_at = nil
    state.save!
  end

  def failure!
    update(
      processed_at: Time.current,
      pushed_at: nil,
    )
  end

  def success!
    update(
      processed_at: Time.current,
      pushed_at: Time.current,
    )
  end
end
