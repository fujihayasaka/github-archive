# typed: true
# frozen_string_literal: true

class StopTrialJob < ApplicationJob
  queue_as :stop_growth_trial

  retry_on_dirty_exit

  CLEANUP_BATCH_SIZE = 100

  def perform(billable_entity:, sku_name:)
    started_at = GitHub::Dogstats.monotonic_time
    success = false

    begin
      with_write do
        trial = make_trial(billable_entity: billable_entity, sku_name: sku_name)

        if trial.reset_on_expiration?
          BulkDisableService.disable_service_on_private_repos(trial.billable_entity, User.ghost, service_for_sku(trial.sku_name))
        end

        trial.disable(actor: User.ghost)

        if FeatureFlag.vexi.enabled?(:ghas_enable_trial_access_for_existing_users, billable_entity, default: false)
          cleanup_pre_trial_repos_table(
            billable_entity: billable_entity,
            sku_name: sku_name
          )
        end
      end
      success = true
    rescue StandardError => e # rubocop:todo Lint/RescueException
      Failbot.report(e, {
        "code.namespace": self.class.name,
        "code.function": __method__,
      })
    ensure
      # Note that this doesn't include all times we stop the trial yet
      GitHub.dogstats.increment("secret_scanning.stop_trial_job.complete", tags: ["success:#{success}"])
      GitHub.dogstats.distribution("secret_scanning.stop_trial_job.duration", GitHub::Dogstats.duration(started_at))
    end
  end # perform

  private

  sig { params(sku_name: String).returns(Symbol) }
  def service_for_sku(sku_name)
    case sku_name
    when EnterpriseCloudOnboard::SecretProtectionTrial::SKU_NAME
      :token_scanning
    when EnterpriseCloudOnboard::CodeSecurityTrial::SKU_NAME
      :code_security
    else
      raise "Unknown SKU name: #{sku_name}"
    end
  end

  sig { params(billable_entity: T.any(Business, Organization), sku_name: String).returns(EnterpriseCloudOnboard::SKUTrial) }
  def make_trial(billable_entity:, sku_name:)
    case sku_name
    when EnterpriseCloudOnboard::SecretProtectionTrial::SKU_NAME
      EnterpriseCloudOnboard::SecretProtectionTrial.new(billable_entity: billable_entity)
    when EnterpriseCloudOnboard::CodeSecurityTrial::SKU_NAME
      EnterpriseCloudOnboard::CodeSecurityTrial.new(billable_entity: billable_entity)
    else
      raise "Unknown SKU name: #{sku_name}"
    end
  end

  sig { params(billable_entity: T.any(Business, Organization), sku_name: String).void }
  def cleanup_pre_trial_repos_table(billable_entity:, sku_name:)
    SecurityProductsEnablement::PreGhasSKUTrialEnabledRepository.where(
      target_id: billable_entity.id,
      target_type: billable_entity.class.name,
      sku_name: sku_name
    ).in_batches(of: CLEANUP_BATCH_SIZE, &:delete_all)
  end
end
