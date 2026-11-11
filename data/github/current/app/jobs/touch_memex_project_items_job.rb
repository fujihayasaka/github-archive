# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class TouchMemexProjectItemsJob < ApplicationJob
  queue_as :touch_memex_project_items

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  locked_by timeout: 5.minutes, key: ->(job) {
    job.arguments[0]
  }

  MAX_THROTTLE_RETRIES = 5
  METRIC_INDEX = "touch_memex_project_items_job"

  def perform(issue)
    memex_project_items = issue.memex_project_items
    return unless memex_project_items.any?

    with_write do
      memex_project_items.touch_all
    end
  end
end
