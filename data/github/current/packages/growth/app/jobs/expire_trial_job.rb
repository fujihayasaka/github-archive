# typed: true
# frozen_string_literal: true

class ExpireTrialJob < ApplicationJob
  queue_as :growth_trial

  schedule interval: 12.hours, condition: -> { !GitHub.enterprise? }

  retry_on_dirty_exit

  def perform(batch_size: 10_000)
    now = Date.current

    # disable Secret Protection trials
    EnterpriseCloudOnboard::SecretProtectionTrial.active_trials(batch_size).each do |batch|
      EnterpriseCloudOnboard::SecretProtectionTrial.throttle do
        disable_trials(batch, now)
      end
    end

    # disable Code Security trials
    EnterpriseCloudOnboard::CodeSecurityTrial.active_trials(batch_size).each do |batch|
      EnterpriseCloudOnboard::CodeSecurityTrial.throttle do
        disable_trials(batch, now)
      end
    end
  end # perform

  private

  sig { params(trials: T::Array[EnterpriseCloudOnboard::SKUTrial], now: Date).void }
  def disable_trials(trials, now)
    with_write do
      trials.each do |trial|
        expires_at = trial.expires_at
        next if expires_at.nil?
        next if T.must(expires_at) + 1.day > now

        if trial.reset_on_expiration?
          StopTrialJob.perform_now(billable_entity: trial.billable_entity, sku_name: trial.sku_name)
          next
        end

        trial.disable(actor: User.ghost)
      end
    end
  end
end
