# typed: true
# frozen_string_literal: true

module Actions
  class UpdateActionsPatternsJob < ApplicationJob
    queue_as :update_actions_patterns

    retry_on_dirty_exit

    BATCH_SIZE = 100
    MAX_RUNTIME = 60
    MAX_THROTTLE_RETRIES = 5

    # performs batch operations on the allowed_action_patterns table
    # by deleting the old patterns and inserting the new patterns
    def perform(allowlist_id, delete_pattern_ids, new_patterns)
      end_at = Time.now.to_f + MAX_RUNTIME
      delete_pattern_ids ||= []
      new_patterns ||= []

      while Time.now.to_f < end_at
        if ActionsPolicy::Allowlist.find_by(id: allowlist_id).nil?
          return
        end

        if delete_pattern_ids.any?
          batch = delete_pattern_ids.shift(BATCH_SIZE)

          ActionsPolicy::AllowedActionPattern.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
            with_write do
              ActionsPolicy::AllowedActionPattern.where(id: batch).delete_all
            end
          end
        end

        if new_patterns.any?
          batch = new_patterns.shift(BATCH_SIZE)
          batch_hashes = batch.map { |value| build_allowed_action_pattern(allowlist_id, value) }

          ActionsPolicy::AllowedActionPattern.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
            with_write do
              ActionsPolicy::AllowedActionPattern.transaction do
                ActionsPolicy::AllowedActionPattern.insert_all(batch_hashes)
                raise ActiveRecord::Rollback if ActionsPolicy::Allowlist.find_by(id: allowlist_id).nil?
              end
            end
          end
        end

        if delete_pattern_ids.empty? && new_patterns.empty?
          return
        end
      end

      if (delete_pattern_ids.any? || new_patterns.any?) && ActionsPolicy::Allowlist.find_by(id: allowlist_id).present?
        Actions::UpdateActionsPatternsJob.perform_later(allowlist_id, delete_pattern_ids, new_patterns)
      end
    end

    def build_allowed_action_pattern(allowlist_id, value)
      record = ActionsPolicy::AllowedActionPattern.new(
        actions_allowlist_id: allowlist_id,
        value: value,
        created_at: Time.now.utc,
        updated_at: Time.now.utc
      )

      record.attributes
    end
  end
end
