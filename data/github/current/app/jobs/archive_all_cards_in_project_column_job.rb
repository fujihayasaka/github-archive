# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: false
# frozen_string_literal: true

# ArchiveAllCardsInProjectColumnJob does exactly what the class name says:
# it archives all of the ProjectCards belonging to the provided column. Hooray!
#
# Call `ProjectColumn#archive_all_cards` to enqueue the job

class ArchiveAllCardsInProjectColumnJob < BatchedJob
  queue_as :archive_project_cards
  retry_on_dirty_exit

  def next_batch(project_column_id, timestamp: Time.now.utc, offset_item_id: 0, **options)
    return unless @column = ProjectColumn.find(project_column_id)
    return unless @project = @column.project
    GitHub.context.push(project_archive_cards_from_job: @project.id)
    Audit.context.push(project_archive_cards_from_job: @project.id)
    @column.get_cards_batch(timestamp: timestamp, offset_item_id: offset_item_id, batch_size: self.class::BATCH_SIZE)
  end

  def process_batch(batch, *args, **options)
    with_write do
      @column.archive_cards_batch! batch
    end
  end

  def ensure_perform(finished_successfully:, **options)
    # unlock here only if all batches were processed
    if finished_successfully
      with_write do
        @project&.unlock(Project::ProjectLock::CARD_ARCHIVING)
      end
    end
  end
end
