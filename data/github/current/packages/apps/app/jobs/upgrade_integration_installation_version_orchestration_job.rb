# typed: true
# frozen_string_literal: true

# Orchestrates the upgrade of all installations for an integration to a target version.
#
# Responsibilities:
# 1. Validates that the target version is still the latest (not stale)
# 2. Discovers all distinct outdated version numbers across installations
# 3. Fans out one UpgradeIntegrationInstallationVersionBatchedJob per outdated version

class UpgradeIntegrationInstallationVersionOrchestrationJob < ApplicationJob
  include GitHub::Memoizer

  queue_as :upgrade_integration_installation_version
  exempt_from_tenant_context_requirement
  retry_on_dirty_exit

  sig { params(integration_id: Integer, target_version_number: Integer, updating_actor_id: T.nilable(Integer)).void }
  def perform(integration_id:, target_version_number:, updating_actor_id: nil)
    if newer_version_published?
      emit_stale_version_dropped
      return
    end

    if outdated_version_numbers.empty?
      emit_no_outdated_installations
      return
    end

    # Fan out: one BatchedJob per outdated version
    outdated_version_numbers.each do |outdated_version_number|
      UpgradeIntegrationInstallationVersionBatchedJob.perform_later(
        integration_id: integration_id,
        target_version_number: target_version_number,
        outdated_version_number: outdated_version_number,
        updating_actor_id: updating_actor_id,
        popular: popular_integration?,
      )
    end

    emit_total_installations
  end

  private

  def newer_version_published?
    !target_version_still_latest?
  end

  # Returns true when the target version is still the latest version of the integration.
  # Tries the replica first to reduce load on primary; falls back to primary to guard
  # against false negatives caused by replication lag.
  def target_version_still_latest?
    target_version_matches_latest_on_replica? || target_version_matches_latest_on_primary?
  end

  def target_version_matches_latest_on_replica?
    latest_version_number(role: :reading) == target_version_number
  end

  def target_version_matches_latest_on_primary?
    latest_version_number(role: :writing) == target_version_number
  end

  def latest_version_number(role:)
    ActiveRecord::Base.connected_to(role: role) do
      integration.versions.reorder(id: :desc).pick(:number)
    end
  end

  memoize def outdated_version_numbers
    integration
      .installations
      .select(:integration_version_number)
      .distinct
      .order(:integration_version_number)
      .pluck(:integration_version_number)
      .select { |version_number| version_number < target_version_number }
  end

  def emit_stale_version_dropped
    GitHub.dogstats.count(
      "job.upgrade_integration_installation_version_orchestration_job.drop_older_version",
      1,
      tags: tags_for_integration,
    )
  end

  def emit_no_outdated_installations
    GitHub.dogstats.count(
      "job.upgrade_integration_installation_version_orchestration_job.no_outdated_installations",
      1,
      tags: tags_for_integration,
    )
  end

  def emit_total_installations
    GitHub.dogstats.distribution(
      "job.upgrade_integration_installation_version_orchestration_job.total_installations",
      installations_count,
      tags: tags_for_integration,
    )
  end

  memoize def tags_for_integration
    tags = ["popular:#{popular_integration?}"]
    tags << "integration:#{integration.slug}" if popular_integration?
    tags
  end

  # When an integration exceeds this threshold we tag metrics with the integration
  # slug, enabling per-app dashboards and alerts. Below it we only emit the
  # generic "popular:false" tag to avoid high-cardinality metric explosion.
  MINIMUM_POPULAR_INSTALLATIONS_COUNT = 100_000

  sig { returns(Integration) }
  memoize def integration
    Integration.find_by!(id: arguments.dig(0, :integration_id))
  end

  sig { returns(Integer) }
  memoize def target_version_number
    arguments.dig(0, :target_version_number)
  end

  sig { returns(T::Boolean) }
  memoize def popular_integration?
    installations_count > MINIMUM_POPULAR_INSTALLATIONS_COUNT
  end

  sig { returns(Integer) }
  memoize def installations_count
    integration.installations.count
  end
end
