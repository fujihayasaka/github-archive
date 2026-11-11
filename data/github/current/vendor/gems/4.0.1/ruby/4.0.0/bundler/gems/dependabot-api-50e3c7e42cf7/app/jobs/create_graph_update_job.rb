# frozen_string_literal: true

require "json"

class CreateGraphUpdateJob < ApplicationJob
  queue_as :default
  default_retries_for_idempotent_jobs

  attr_reader :update_config, :directories

  def perform(update_config:, directories: nil)
    @update_config = update_config
    @directories = directories

    job = create_update_job
    enqueue_update_job(job)
  end

  private

  def create_update_job
    update_config.update_jobs.create!(
      command: :graph,
      directories: directories,
      trigger_type: "graph",
    )
  end

  def enqueue_update_job(job)
    PrioritizedJobs::StartUpdateJob.perform_later(job)
  end
end
