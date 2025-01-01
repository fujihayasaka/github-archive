# typed: true
# frozen_string_literal: true

class RepositoryMirrorJob < ApplicationJob
  queue_as :repository_mirror
  retry_on_dirty_exit
  # Exception raised when the job fails due to git command failure.
  class Failed < StandardError
  end

  def perform(repository_id)
    set_status_in_cache("mirror-timestamp:#{repository_id}", Time.now.to_s)
    GitHub.dogstats.increment("repository_mirror_job.attempts")

    repo = Repositories::Public.find_active!(repository_id)
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

  rescue => e # rubocop:todo Lint/GenericRescue
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
