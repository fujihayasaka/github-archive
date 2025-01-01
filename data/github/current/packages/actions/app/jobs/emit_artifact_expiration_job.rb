# typed: true
# frozen_string_literal: true

class EmitArtifactExpirationJob < ApplicationJob
  include GitHub::Tracing

  READ_BATCH_SIZE = 4000
  WRITE_BATCH_SIZE = 100

  queue_as :emit_artifact_expiration
  schedule interval: 15.minutes, condition: -> { !GitHub.enterprise? }
  retry_on_dirty_exit
  retry_on_recoverable_exceptions
  retry_on GitHub::Restraint::UnableToLock, wait: 1.minute, attempts: 10

  trace_method :perform

  def perform
    return unless FeatureFlag.vexi.enabled_or_raise?(:emit_artifact_expiration) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage

    restraint = GitHub::Restraint.new
    lock_key = "emit_artifact-expiration_job"
    max_concurrent_jobs = 1
    lock_ttl = 1.hour
    restraint.lock!(lock_key, max_concurrent_jobs, lock_ttl) do
      emit_artifact_expiration
    rescue ActiveRecord::RecordNotFound, StandardError => e # rubocop:todo Lint/RescueException
      Failbot.report(e)
      raise e
    end
  end

  private

  def emit_artifact_expiration
    GitHub.dogstats.increment("emit_artifact_expiration_job.start")
    end_at = 10.minutes.from_now
    # This is hard-coded so we can have coverage of all artifacts expiring since this is deployed.
    # We will remove this after retention (400 days) has passed and we have coverage of all artifacts expiring.
    artifact_job_start_date = Time.new(2023, 6, 23)
    time_end = Time.now

    total_artifacts = 0

    loop do
      artifacts = fetch_expired_artifacts_batch(artifact_job_start_date, time_end)
      total_artifacts += artifacts.count

      break if artifacts.empty?

      set_expiration_emitted(artifacts)

      artifacts.each do |artifact|
        emit_artifact_expired(artifact)
      end

      GitHub.dogstats.count("emit_artifact_expiration_job.expired_artifacts_processed_batch", artifacts.count)

      break if Time.now > end_at
    end

    GitHub.dogstats.count("emit_artifact_expiration_job.expired_artifacts_processed", total_artifacts)
    GitHub.dogstats.increment("emit_artifact_expiration_job.finish")
  end

  def fetch_expired_artifacts_batch(time_start, time_end)
    Artifact
      .from("artifacts FORCE INDEX(index_artifacts_on_expiration_emitted_and_expires_at)")
      .where("expires_at between :expires_at_start AND :expires_at_end AND expiration_emitted = false",
        expires_at_start: time_start,
        expires_at_end: time_end
      )
      .limit(READ_BATCH_SIZE)
      .to_a
  end

  def emit_artifact_expired(artifact)
    artifact.emit_artifact_expired_event
    GitHub.dogstats.increment("emit_artifact_expiration_job.expired_artifacts_emitted")
  end

  def set_expiration_emitted(artifacts)
    repo_id_pairs = group_artifact_ids_by_repository_id(artifacts.pluck(:repository_id, :id))
    total_expired_count = 0

    repo_id_pairs.each do |repository_id, artifact_ids|
      artifact_ids.in_groups_of(WRITE_BATCH_SIZE) do |batch|
        ActiveRecord::Base.connected_to(role: :writing) do
          expired_count = Artifact.throttle do
            Artifact.where(repository_id: repository_id, id: batch, expiration_emitted: false).update_all(expiration_emitted: true)
          end
          total_expired_count += expired_count
          GitHub.dogstats.count("emit_artifact_expiration_job.expired_artifacts_updated_batch", expired_count)
        end
      end
    end

    GitHub.dogstats.count("emit_artifact_expiration_job.expired_artifacts_updated_total", total_expired_count)
    GitHub.dogstats.count("emit_artifact_expiration_job.duplicate_artifacts_emitted", artifacts.count - total_expired_count)
  end

  # Utility function to group IDs by repository_id so that all SQL calls can have the primary sharding key included later
  # Expected input is a list of of plucked repoID and ID pairs in the format [[repository_id, id], [repository_id, id]...]
  # Returns in the format [[repository_id, [id, id, id]], [repository_id, [id, id, id]]...
  def group_artifact_ids_by_repository_id(input_data)
    # https://stackoverflow.com/questions/59421316/rails-group-by-column-and-select-column
    input_data.group_by(&:shift).transform_values(&:flatten)
  end
end
