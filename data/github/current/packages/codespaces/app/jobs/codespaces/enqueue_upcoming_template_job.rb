# typed: true
# frozen_string_literal: true

module Codespaces
  # Enqueues upcoming template job
  class EnqueueUpcomingTemplateJob < CodespacesJob
    locked_by timeout: 1.hour, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC
    retry_on_dirty_exit

    schedule interval: 10.minutes, condition: -> { !GitHub.enterprise? }

    BATCH_SIZE = 100

    def perform
      Codespaces::PrebuildTemplateCreationSchedule.upcoming.includes(:configuration).find_each(batch_size: BATCH_SIZE) do |template_schedule|
        next if template_schedule.configuration.nil? || template_schedule.configuration&.disabled?

        log_schedule(template_schedule)
        next_delivery_at = template_schedule.next_delivery_at
        Codespaces::ProcessScheduledTemplateJob.set(wait_until: next_delivery_at).perform_later(template_schedule_id: template_schedule.id, queued_next_delivery_at: next_delivery_at)
      end

    rescue Aqueduct::Worker::JobKilled => e
      GitHub.dogstats.increment("codespaces.enqueue_upcoming_template_job.dirty_exit")
      raise
    end

    private

    def log_schedule(template_schedule)
      GitHub.logger.info(
        "template schedule info",
        "gh.catalog_service" => "github/codespaces",
        "gh.codespaces.prebuild_configuration.id" => template_schedule.codespace_prebuild_configuration_id,
        "gh.codespaces.prebuild_template.schedule_id" => template_schedule.id,
        "gh.codespaces.prebuild_template.schedule_next_delivery_at" => template_schedule.next_delivery_at
      )
    end
  end
end
