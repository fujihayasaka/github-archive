# typed: strict
# frozen_string_literal: true

module CopilotSpaces
  class CleanupCopilotSpacesJob < BatchedJob
    queue_as :cleanup_copilot_spaces
    retry_on_dirty_exit

    BATCH_SIZE = 100

    around_enqueue do |_job, block|
      block.call unless GitHub.enterprise?
    end

    sig do
      params(
        args: T.untyped,
        timestamp: Time,
        offset_item_id: Integer,
        progress: Integer,
        options: T.untyped
      ).returns(T.nilable(T::Array[CopilotSpace]))
    end
    def next_batch(*args, timestamp: Time.now.utc, offset_item_id: 0, progress: 0, **options)
      owner_id = options[:owner_id]

      return [] unless owner_id

      CopilotSpace.where(owner_id: owner_id, owner_type: "User").where("id > ?", offset_item_id).order(:id).limit(BATCH_SIZE).to_a
    end

    sig { params(batch: T::Array[CopilotSpace], args: T.untyped, options: T.untyped).void }
    def process_batch(batch, *args, **options)
      batch.each do |copilot_space|
        with_write do
          copilot_space.destroy
        end
      end
    end
  end
end
