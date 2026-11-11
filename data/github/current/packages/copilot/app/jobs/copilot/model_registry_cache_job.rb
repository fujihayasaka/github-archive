# typed: strict
# frozen_string_literal: true

module Copilot
  class ModelRegistryCacheJob < CopilotJob
    exempt_from_tenant_context_requirement
    retry_on_dirty_exit

    queue_as :model_registry_cache

    locked_by timeout: 30.seconds, key: DEFAULT_LOCK_PROC
    schedule interval: 1.minute
    gate_with_feature_flag :copilot_model_registry_cache_job

    sig { void }
    def perform
      return if GitHub.enterprise?

      GitHub.logger.info("Copilot::ModelRegistryCacheJob - Running Copilot Model Registry Cache Job")
      Copilot::ModelsRegistryCache.save_models
      GitHub.logger.info("Copilot::ModelRegistryCacheJob - Finished Copilot Model Registry Cache Job")
    rescue StandardError => e
      # Log the error at the application level for observability, then re-raise
      # so that CopilotJob#collect_metrics can emit the error metric.
      GitHub.logger.error("Copilot::ModelRegistryCacheJob - Error in Copilot Model Registry Cache Job: #{e.message}")
      raise
    end
  end
end
