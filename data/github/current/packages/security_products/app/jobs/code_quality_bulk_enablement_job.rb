# typed: strict
# frozen_string_literal: true

class CodeQualityBulkEnablementJob < ApplicationJob
  BATCH_SIZE = 100

  queue_as :code_quality_bulk_enablement
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  locked_by timeout: 10.minutes, key: ->(job) do
    args = job.arguments[0]
    "code_quality_bulk_enablement-#{args&.fetch(:organization_id)}"
  end

  sig do
    params(
      organization_id: Integer,
      actor_id: Integer,
      enabled: T::Boolean,
    ).void
  end
  def perform(organization_id:, actor_id:, enabled:)
    organization = Organization.find_by(id: organization_id)
    if organization.nil?
      GitHub.logger.info("Organization not found", "gh.org.id": organization_id)
      return
    end

    actor = User.find_by(id: actor_id)
    if actor.nil?
      GitHub.logger.info("Actor not found", "gh.actor.id": actor_id)
      return
    end

    GitHub.logger.info("Starting code quality bulk enablement",
      "gh.org.id": organization.id,
      "gh.actor.id": actor.id,
      "gh.code_quality.enabled": enabled,
    )

    tags = ["enabled:#{enabled}"]
    CodeQualityEnablement.increment_enablement(metric: "bulk.started", tags:)
    started_at = GitHub::Dogstats.monotonic_time

    enqueued = 0
    skipped_archived = 0
    skipped_code_quality_not_available = 0

    organization.repositories.active.in_batches(of: BATCH_SIZE) do |batch|
      batch.each do |repository|
        if repository.archived?
          skipped_archived += 1
          next
        end

        if CodeQuality.available?(repository)
          ApplyCodeQualityToRepositoryJob.perform_later(
            repository_id: repository.id,
            actor_id: actor.id,
            enabled: enabled,
            organization_id: organization.id,
          )
          enqueued += 1
        else
          skipped_code_quality_not_available += 1
        end
      end
    end

    active_repos = enqueued + skipped_archived + skipped_code_quality_not_available

    # active_repos = every repository in the org's `Repository.active` scope
    # (i.e. `active = true`) that we considered for this bulk run. That scope
    # still yields archived repositories, so the total is enqueued + skipped
    # (archived) + skipped (Code Quality not available). It is the denominator
    # for bulk adoption / skip ratios.
    CodeQualityEnablement.distribute_enablement(metric: "bulk.active_repos", value: active_repos, tags:)
    CodeQualityEnablement.distribute_enablement(metric: "bulk.enqueued_repos", value: enqueued, tags:)
    CodeQualityEnablement.distribute_enablement(metric: "bulk.duration", value: GitHub::Dogstats.duration(started_at), tags:)

    { "archived" => skipped_archived, "code_quality_not_available" => skipped_code_quality_not_available }.each do |reason, count|
      next unless count.positive?

      CodeQualityEnablement.increment_enablement(metric: "bulk.skipped", tags: tags + ["reason:#{reason}"], by: count)
    end

    GitHub.logger.info("Finished enqueuing code quality bulk enablement jobs",
      "gh.org.id": organization.id,
      "gh.code_quality.enabled": enabled,
      "gh.code_quality.enqueued": enqueued,
      "gh.code_quality.skipped_archived": skipped_archived,
      "gh.code_quality.skipped_code_quality_not_available": skipped_code_quality_not_available,
    )
  end
end
