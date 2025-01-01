# typed: true
# frozen_string_literal: true

class Codespaces::CleanUpStuckProvisioningJob < CodespacesJob
  schedule interval: 5.minutes, condition: -> { !GitHub.enterprise? }

  retry_on_dirty_exit

  def perform
    return unless FeatureFlag.vexi.enabled_or_raise?(:codespaces_clean_up_stuck_provisioning) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage

    deprovisioned = 0
    with_write do
      Codespace.stuck_provisioning.find_each do |codespace|
        state = codespace.state
        codespace.pending_async_operations.create_codespace.first&.mark_as_failed(failure_reason: "StuckProvisioning")
        Codespace.throttle_with_retry { codespace.deprovision!(reason: Codespace.deletion_reasons[:stuck_provisioning]) }
        if codespace.vscs_target&.to_sym == :production
          # Only log/emit metrics for production codespaces
          deprovisioned += 1
          GitHub.logger.info(
            "Codespaces::CleanUpStuckProvisioningJob found codespace to deprovision",
            "gh.catalog_service" => "github/codespaces",
            "gh.codespaces.name" => codespace.name,
            "gh.codespaces.guid" => codespace.guid,
            "gh.codespaces.state" => state,
            "gh.codespaces.environment_state" => codespace.environment_data&.state,
            "gh.codespaces.created_at" => codespace.created_at,
          )
        end
      end
    end

    GitHub.dogstats.count("codespaces.clean_up_stuck_provisioning.deprovisioned", deprovisioned)
  end
end
