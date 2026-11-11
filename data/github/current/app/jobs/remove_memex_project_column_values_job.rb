# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class RemoveMemexProjectColumnValuesJob < ApplicationJob
  queue_as :remove_memex_project_column_values

  BATCH_SIZE = 100

  retry_on_dirty_exit

  resolve_tenant_context do |column_id, _ids|
    column = MemexProjectColumn.find_by(id: column_id)
    column&.memex_project&.resolve_tenant
  end

  # Given a MemexProjectColumn id and the id of one of the options for the
  # column, iterate through each of the values with the given option id and
  # destroy it.
  #
  # Essentially, when a user deletes an option for say a single select column,
  # we want to remove all values with the deleted option.
  #
  # column_id - the primary key of the MemexProjectColumn
  # ids - one or multiple ids of the option/iteration that have presumably already been deleted
  #
  # returns nothing
  def perform(column_id, ids)
    return tag_404 unless column = MemexProjectColumn.find_by(id: column_id)
    return unless column.single_select? || column.iteration?

    if column.single_select?
      ids_to_remove = Array(ids) - column.settings_option_ids
    else
      ids_to_remove = Array(ids) - column.settings_iteration_ids - column.settings_completed_iteration_ids
    end

    column
      .memex_project_column_values
      .where(value: ids_to_remove)
      .in_batches(of: BATCH_SIZE) do |relation|
      log("status:200") do
        MemexProjectColumnValue.throttle do
          with_write do
            relation.destroy_all
          end
        end
      end
    end
  end

  private

  def tag_404
    log("status:404")
  end

  def log(tags)
    yield if block_given?

    GitHub.dogstats.increment(
      "memex.remove_memex_project_column_values_job",
      tags: [tags],
    )
  end
end
