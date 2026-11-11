# frozen_string_literal: true

require "json"

class CreateGraphUpdateJob < ApplicationJob
  queue_as :default
  default_retries_for_idempotent_jobs

  attr_reader :update_config, :directories, :github_request_id, :base_commit_sha

  def perform(update_config:, directories: nil, github_request_id: nil, base_commit_sha: nil)
    @update_config = update_config
    @directories = directories
    @github_request_id = github_request_id
    @base_commit_sha = base_commit_sha

    job = create_update_job
    enqueue_update_job(job)
  end

  private

  def create_update_job
    update_config.update_jobs.create!(
      command: :graph,
      directories: directories,
      github_request_id: github_request_id,
      trigger_type: "graph",
      base_commit_sha: base_commit_sha,
    )
  end

  def enqueue_update_job(job)
    PrioritizedJobs::StartUpdateJob.perform_later(job)
  end
end
