# typed: true
# frozen_string_literal: true

class QueueCollectMetricsJob < ApplicationJob
  schedule interval: 1.day, condition: -> { GitHub.enterprise? }
  queue_as :collect_metrics
  retry_on_dirty_exit

  def perform
    return unless GitHub.enterprise?
    CollectMetricsJob.perform_later
  end
end
