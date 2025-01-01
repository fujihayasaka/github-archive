# typed: true
# frozen_string_literal: true

class CommitUploadManifestJob < ApplicationJob
  queue_as :commit_upload_manifest
  retry_on_dirty_exit

  attr_reader :manifest, :status

  MAX_ATTEMPTS = 4

  RETRY_ERRORS = [ActiveRecord::RecordNotFound, JobStatus::NotFound, Git::Ref::ComparisonMismatch,
    Net::ReadTimeout, Net::OpenTimeout, GitHub::DGit::InsufficientQuorumError, GitHub::KV::UnavailableError].freeze

  USER_ERRORS = [Git::Ref::RepositoryRuleViolationError, GitRPC::RequestTooLarge].freeze

  retry_on(*RETRY_ERRORS, wait: :polynomially_longer, attempts: MAX_ATTEMPTS) do |job, error|
    job.handle_failure(error)
  end

  def perform(manifest_id, status_id = nil, options = {})
    UploadManifest.throttle do
      @manifest = UploadManifest.find(manifest_id)
      CommitUploadManifestJobStatus.throttle do
        @status = find_or_create_status(manifest_id, @manifest.uploader_id)

        # We don't use JobStatus#track here because it will set the status to error prematurely
        # in the case of a retryable failure in UploadManifest#commit. CommitUploadManifestJobStatuses are stored
        # on Mysql5.
        with_write do
          status.started!
          manifest.commit
          status.success!
        end
      end
    end
  rescue Freno::Throttler::Error, *RETRY_ERRORS
    raise
  rescue => error # rubocop:todo Lint/GenericRescue
    handle_failure(error)
  end

  def find_or_create_status(manifest_id, uploader_id)
    @status ||= CommitUploadManifestJobStatus.find(CommitUploadManifestJobStatus.job_id(manifest_id))
    @status ||= with_write { CommitUploadManifestJobStatus.create(id: manifest_id, uploader_id:) } unless @status
    @status
  end

  def handle_failure(error)
    if manifest
      with_write { UploadManifest.throttle { manifest.state_failed! } }
      Failbot.push("gh.user.id": manifest.uploader.id, "gh.repo.id": manifest.repository.id)
    end
    error_message = nil
    failed_runs = T.let([], T::Array[RuleEngine::RuleRun])
    if error.is_a?(Git::Ref::RepositoryRuleViolationError) && error.detailed_message.present?
      # Extract the specific error message from the detailed message
      error_message = error.detailed_message.strip.split("\n\n")[1]
      failed_runs = error.failed_runs
    elsif error.is_a?(GitRPC::RequestTooLarge)
      error_message = "The file is too large and cannot be uploaded. Consider creating the file in a " \
        "local clone and pushing it to GitHub"
    end
    CommitUploadManifestJobStatus.throttle do
      with_write { status&.error!(error_message, failed_runs) }
    end

    raise error unless USER_ERRORS.include?(error.class)
  rescue Freno::Throttler::Error
    raise StandardError.new("Throttled while reporting failure, cannot retry")
  end
end
