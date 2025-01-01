# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class HydroDependencyGraphPlatformOnPushJob < Repositories::PushHydroMessageJob
  extend T::Helpers

  retry_on_dirty_exit

  queue_as :hydro_dependency_graph_platform_on_push

  # Public: process a Hydro message
  sig { void }
  def perform
    return unless dgp_eligible_push?

    eligible_updates = ref_updates.select do |ru|
      return false if ru.deleted?
      return false unless ru.ref.starts_with?("refs/heads/")
      true
    end

    GitHub.dogstats.count("hydro_dependency_graph_platform_on_push_job.ref_updates", eligible_updates.size)
    instrument_dgp_repository_push(eligible_updates)
  end

  def dgp_eligible_push?
    return false if GitHub.enterprise?
    return false unless GitHub.dependency_graph_enabled?
    return false unless repository.dependency_graph_enabled?
    return false if repository.owner&.spammy?

    true
  end

  def instrument_dgp_repository_push(eligible_updates)
    return unless eligible_updates.any?

    payload = {
      request_context: GitHub.context,
      repository: repository,
      owner: repository.owner,
      actor: pusher,
      updates: eligible_updates,
      pushed_at: pushed_at,
    }

    GlobalInstrumenter.instrument("dependency_graph.repository_push", payload)
  end
end
