# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class BatchedEnqueueMemexProjectColumnIterationUpdateJob < BatchedJob
  queue_as :enqueue_memex_project_column_iteration_update
  schedule interval: 12.hours

  retry_on_dirty_exit

  BATCH_SIZE = 500

  exempt_from_tenant_context_requirement

  def process_batch(batch, *args, **options)
    batch.each do |column|
      MemexProjectColumnIterationUpdateJob.perform_later(column.id)
    end
  end

  private

  def next_batch(*args, timestamp: Time.now.utc, offset_item_id: 0, progress: 0, **options)
    MemexProjectColumn
      .iteration
      .where("id > ?", offset_item_id)
      .limit(BATCH_SIZE)
      .order(id: :asc)
  end
end
