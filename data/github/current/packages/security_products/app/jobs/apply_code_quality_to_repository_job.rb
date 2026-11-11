# typed: strict
# frozen_string_literal: true

class ApplyCodeQualityToRepositoryJob < ApplicationJob
  queue_as :code_quality_bulk_enablement
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  locked_by timeout: 5.minutes, key: ->(job) {
    "apply_code_quality_repo-#{job.arguments[0]&.fetch(:repository_id)}"
  }

  retry_on StandardError, wait: :polynomially_longer, attempts: 3 do |job, error|
    GitHub.logger.error("Code quality enablement failed after retries",
      "code.namespace": job.class.name,
      "code.function": job.method(:perform).name.to_s,
      "gh.repo.id": job.arguments.first&.fetch(:repository_id, nil),
      "gh.org.id": job.arguments.first&.fetch(:organization_id, nil),
      exception: error,
    )
    Failbot.report(error, {
      "code.namespace": job.class.name,
      "code.function": job.method(:perform).name.to_s,
      "gh.repo.id": job.arguments.first&.fetch(:repository_id, nil),
    })
  end

  sig do
    params(
      repository_id: Integer,
      actor_id: Integer,
      enabled: T::Boolean,
      organization_id: Integer,
    ).void
  end
  def perform(repository_id:, actor_id:, enabled:, organization_id:)
    repository = Repository.find_by(id: repository_id)
    if repository.nil?
      GitHub.logger.info("Repository not found",
        "code.namespace": self.class.name,
        "code.function": __method__,
        "gh.repo.id": repository_id,
      )
      return
    end

    if repository.owner_id != organization_id || !repository.owner.is_a?(Organization)
      GitHub.logger.warn("Repository owner mismatch",
        "code.namespace": self.class.name,
        "code.function": __method__,
        "gh.repo.id": repository_id,
        "gh.org.id": organization_id,
        "gh.repo.owner_id": repository.owner_id,
      )
      return
    end

    actor = User.find_by(id: actor_id)
    if actor.nil?
      GitHub.logger.info("Actor not found",
        "code.namespace": self.class.name,
        "code.function": __method__,
        "gh.actor.id": actor_id,
      )
      return
    end

    service_manager = SecurityProduct::ServiceManager.new(repository)

    result = if enabled
      service_manager.toggle_services(actor, services_to_enable: [[:code_quality, { action: :enable, skip_if_enabled: true }]])
    else
      service_manager.toggle_services(actor, services_to_disable: [[:code_quality, { skip_if_disabled: true }]])
    end

    success = !result.error?
    result_tags = ["source:bulk_org", "enabled:#{enabled}", "success:#{success}"]
    CodeQualityEnablement.increment_enablement(metric: "repo.result", tags: result_tags)

    if result.error?
      GitHub.logger.warn("Code quality enablement failed",
        "code.namespace": self.class.name,
        "code.function": __method__,
        "gh.repo.id": repository_id,
        "gh.org.id": organization_id,
        "gh.code_quality.enabled": enabled,
        "gh.code_quality.error": result.error.to_s,
      )
      return
    end

    GitHub.logger.info("Code quality enablement applied",
      "code.namespace": self.class.name,
      "code.function": __method__,
      "gh.repo.id": repository_id,
      "gh.org.id": organization_id,
      "gh.code_quality.enabled": enabled,
    )
  end
end
