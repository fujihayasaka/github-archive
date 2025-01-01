# typed: true
# frozen_string_literal: true

module Stafftools
  class DisableRepositoryAccessStatus
    delegate :disable_access_job_status, to: :repository
    delegate :disabled?, to: :repository_access, prefix: :repository

    attr_reader :repository, :repository_access

    def initialize(repository)
      @repository = repository
      @repository_access = repository.access
    end

    def job_still_running?
      return false if repository_disabled? ||
        %w[error success].include?(disable_access_job_status)
      true
    end

    def start_tracking_job
      JobStatus.create(id: job_id)
    end

    def job_status
      @job_status ||= JobStatus.find(job_id)
    end

    def track
      job_status.track do
        Stafftools::BulkDmcaTakedown.set_running_state(repository)
        yield
      end
      Stafftools::BulkDmcaTakedown.notify_job_done(repository)
    end

    def error_suspected?
      return true if disable_access_job_status == "error"
      !job_still_running? && !repository_disabled?
    end

    def to_hash
      state = {}
      state[:user_display_status] = display_status
      state
    end

    private

    def display_status
      if repository_disabled?
        "disabled"
      elsif job_still_running?
        disable_access_job_status
      elsif error_suspected?
        "error"
      end
    end

    def job_id
      "disable_repository_access_job_#{repository.id}"
    end
  end
end
