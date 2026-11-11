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

    actor = issue.repository&.owner
    per_item_enabled = FeatureFlag.vexi.enabled?(:memex_per_item_touch_enabled, actor, default: false)

    if FeatureFlag.vexi.enabled?(:projects_instrument_item_touch, default: false)
      GitHub.dogstats.count("#{METRIC_INDEX}.items_touched", memex_project_items.count)
    end

    with_write do
      if per_item_enabled
        GitHub.dogstats.increment("#{METRIC_INDEX}.path.per_item")
        # Touch each item individually to trigger after_commit callbacks,
        # which emit project_item_metadata_update events for each item.
        memex_project_items.each(&:touch)
      else
        GitHub.dogstats.increment("#{METRIC_INDEX}.path.bulk")
        # Bulk touch - more efficient but doesn't trigger individual callbacks
        memex_project_items.touch_all
      end
    end
  end
end
