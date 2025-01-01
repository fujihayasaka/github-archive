# typed: true
# frozen_string_literal: true

class PublishScheduledDiscussionsJob < ApplicationJob
  schedule interval: 1.minute
  queue_as :discussions_scheduled_publish

  retry_on_dirty_exit

  METRIC_DELAY = "discussions.scheduled.publish.delay".freeze
  METRIC_FOUND = "discussions.scheduled.found".freeze
  DOGSTATS_TAGS = ["job:publish_scheduled_discussions"].freeze

  def perform
    return unless FeatureFlag.vexi.enabled?(:scheduled_discussions_job, default: true)

    discussions = Discussion.ready_to_publish

    return if discussions.empty?

    GitHub.dogstats.count(METRIC_FOUND, discussions.size, tags: DOGSTATS_TAGS)
    discussions.each do |discussion|
      with_write do
        discussion.open!

        track_publish_delay(discussion)
      end
    end
  end

  private

  # Emits a histogram sample of “how late was this publish?”
  def track_publish_delay(discussion)
    delay_seconds = Time.current - discussion.publish_at

    GitHub.dogstats.histogram(METRIC_DELAY, delay_seconds, tags: DOGSTATS_TAGS)
  end
end
