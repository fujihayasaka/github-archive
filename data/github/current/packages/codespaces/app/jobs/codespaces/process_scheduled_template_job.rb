# typed: true
# frozen_string_literal: true

module Codespaces
  class ProcessScheduledTemplateJob < CodespacesJob
    locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC
    retry_on_dirty_exit

    def perform(template_schedule_id:, queued_next_delivery_at:)
      template_creation_schedule = Codespaces::PrebuildTemplateCreationSchedule.where(id: template_schedule_id).includes(:configuration).first
      prebuild_configuration = template_creation_schedule&.configuration
      return if template_creation_schedule.nil? || prebuild_configuration.nil? || prebuild_configuration.trigger != :schedule.to_s

      current_next_delivery_at = template_creation_schedule.next_delivery_at

      # checks if record has already been processed
      unless current_next_delivery_at == queued_next_delivery_at
        GitHub.dogstats.increment("codespaces.process_scheduled_template_job.record_already_processed")
        return
      end

      # trigger dynamic workflow to create template
      prebuild_configuration.trigger_prebuild_template_creation

      # update next delivery at time
      Codespaces::PrebuildTemplateCreationSchedule.throttle_with_retry { template_creation_schedule.update_next_delivery_at }

    rescue Aqueduct::Worker::JobKilled => e
      GitHub.dogstats.increment("process_scheduled_template_job.dirty_exit")
      raise
    end
  end
end
