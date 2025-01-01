# typed: strict
# frozen_string_literal: true

# This job synchronizes the denormalized data for all items in a Memex project. This job updates the memex column
# values to be the same as the current state of the content (e.g. the title of an issue).
#
# In general, this is done automatically by emitted Hydro events (see `GitHub::StreamProcessors::MemexEventsProcessor`),
# but it can happen that events are delayed or lost, so that the denormalized data is out of date. This job is intended
# to provide a manual method of forcing the denormalized data to be updated in case of such an event.
class SyncMemexProjectDenormalizedDataJob < ApplicationJob

  queue_as :sync_memex_project_denormalized_data
  locked_by timeout: 1.hour, key: ->(job) { job.arguments[0] }
  retry_on_dirty_exit

  BATCH_SIZE = 10

  sig { params(memex_project_id: Integer).void }
  def perform(memex_project_id)
    denormalized_columns = MemexProjectColumn
      .where(memex_project_id: memex_project_id, data_type: [:title, :milestone])
      .all

    title_column = T.let(denormalized_columns.find(&:title?), T.nilable(MemexProjectColumn))
    milestone_column = T.let(denormalized_columns.find(&:milestone?), T.nilable(MemexProjectColumn))

    return unless title_column && milestone_column

    items = MemexProjectItem.includes(:content, :issue).where(memex_project_id: memex_project_id)
    items.find_each(batch_size: BATCH_SIZE) do |item|
      # Read the values from the read-only database so that we don't put queries on the write database
      denormalized_title = item.memex_denormalized_title_value
      denormalized_milestone = item.memex_denormalized_milestone_value
      issue = item.issue
      issue_closed_at = issue&.closed_at
      issue_created_at = issue&.created_at
      issue_state = issue&.state
      issue_state_reason = issue&.state_reason

      with_write do
        MemexProjectItem.throttle do
          item.cache_title_column_value(title_column, denormalized_title, User.ghost)
          item.cache_milestone_column_value(milestone_column, denormalized_milestone, User.ghost)

          if issue && item.issue_id == issue.id
            item.update(
              issue_closed_at: issue_closed_at,
              issue_created_at: issue_created_at,
              state: issue_state,
              state_reason: issue_state_reason
            )
          end
        end
      end
    end
  end
end
