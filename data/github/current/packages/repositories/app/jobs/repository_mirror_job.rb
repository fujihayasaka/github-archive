# typed: true
# frozen_string_literal: true

class RepositoryMirrorJob < ApplicationJob
  queue_as :repository_mirror
  retry_on_dirty_exit


  class GitRPCNetworkError < StandardError; end
  ATTEMPTS = 2
  retry_on GitRPCNetworkError, wait: :polynomially_longer, attempts: ATTEMPTS

  # Exception raised when the job fails due to git command failure.
  class Failed < StandardError
  end

  def perform(repository_id)
    set_status_in_cache("mirror-timestamp:#{repository_id}", Time.now.to_s)
    GitHub.dogstats.increment("repository_mirror_job.attempts")

    repo = T.cast(Repositories.domain.by_id(repository_id), Repository) # rubocop:todo GitHub/AvoidCast

    if (repo.deleted? && !repo.soft_creating?) || !repo.exists_on_disk? || repo.archived?
      GitHub.logger.info(
        "Skipping repository mirror job for non-existent, archived, or deleted repo",
        "code.namespace" => self.class.name,
        "code.function" => __method__,
        "gh.repo.id" => repository_id
      )

      # consider this failed for the purposes of the admin view:
      set_status_in_cache("mirror-result:#{repository_id}", "failed")

      GitHub.dogstats.increment("repository_mirror_job.skipped")
      return
    end

    Failbot.push "gh.repo.id": repository_id

    with_write { repo.mirror&.perform! }
    GitHub.logger.info(
      "Performing repository mirror job",
      "code.namespace" => self.class.name,
      "code.function" => __method__,
      "gh.repo.id" => repo.id,
      "gh.repo.source_id" => repo.source_id,
      "gh.spokes.spec" => repo.dgit_spec
    )

    set_status_in_cache("mirror-result:#{repository_id}", "success")
    GitHub.dogstats.increment("repository_mirror_job.success")
    GitHub.logger.info(
      "Successfully performed repository mirror job",
      "code.namespace" => self.class.name,
      "code.function" => __method__,
      "gh.repo.id" => repo.id
    )

  rescue => e # rubocop:todo Lint/RescueException
    if e.is_a?(GitRPC::CommandFailed) && e.message.include?("Network is unreachable") && executions < ATTEMPTS
      raise GitRPCNetworkError, "GitRPC network error during mirror operation"
    end

    if e.is_a?(GitRPC::CommandFailed) && (e.message.include?("not found") || e.message.include?("Network is unreachable"))
      set_status_in_cache("mirror-result:#{repository_id}", "failed")
      GitHub.logger.info(
        "Abandoning repository mirror job",
        "code.namespace" => self.class.name,
        "code.function" => __method__,
        "gh.repo.id" => repository_id,
        "gh.error.message" => e.message
      )
      return
    end

    set_status_in_cache("mirror-result:#{repository_id}", "failed")
    Failbot.push(app: "github-user", "exception.message": e.message)

    GitHub.dogstats.increment("repository_mirror_job.failed")
    GitHub.logger.error(
      :exception => e,
      "code.namespace" => self.class.name,
      "code.function" => __method__,
      "gh.repo.id" => repo&.id
    )

    raise RepositoryMirrorJob::Failed, "Repository mirror failed due to unexpected exception"
  end

  def set_status_in_cache(key, value)
    with_write { Repositories::Kv.store.set(key, value) }
  rescue GitHub::KV::UnavailableError
    # Noop if KV is unavailable. We don't want to hold up performing the rest of the job.
  end
end
