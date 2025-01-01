# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class DisableRepositoryAccessJob < ApplicationJob
  class RepoDisableError < StandardError; end

  queue_as :repository_access

  discard_on ActiveJob::DeserializationError do |_job, error|
    Failbot.report(error)
  end

  locked_by timeout: 10.minutes, key: DEFAULT_LOCK_PROC

  before_enqueue do |job|
    repo = job.arguments[0]
    status = Stafftools::DisableRepositoryAccessStatus.new(repo)
    with_write { status.start_tracking_job }
  end

  def self.status(repo)
    Stafftools::DisableRepositoryAccessStatus.new(repo).job_status
  end

  def perform(repo, reason, user, **opts)
    return if GitHub.flipper[:darkship_dmca_takedown_skip_for_perfomance_reason].enabled?
    take_down_status = Stafftools::DisableRepositoryAccessStatus.new(repo)
    with_write do
      take_down_status.track do
        result = repo.access.disable(reason, user, **opts)

        # Make job fail if we failed to disable one or more repos in network
        failed = !result || (result.is_a?(Hash) && result[:failures].any?)
        raise RepoDisableError.new("Failed to disable repo: #{repo.id}") if failed
      end
    end
  end
end
