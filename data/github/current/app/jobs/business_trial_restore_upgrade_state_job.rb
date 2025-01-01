# typed: true
# frozen_string_literal: true

class BusinessTrialRestoreUpgradeStateJob < ApplicationJob
  queue_as :business_trial_restore_upgrade_state

  retry_on_dirty_exit

  schedule interval: 1.hour, condition: -> { GitHub.billing_enabled? }

  def perform
    restore_trial_state
    restore_organization_upgrade_state
    restore_created_from_coupon_state
  end

  def restore_trial_state
    Business.trial_with_conversion_initiated.where(
      "trial_conversion_initiated_at < ?", 1.day.ago
    ).find_each do |business|
      with_write do
        if business.trial_expired?
          business.transaction do
            business.downgrade_to_free_plan
            business.update! trial_completion_status: :trial_expired, trial_conversion_initiated_at: nil
          end
        else
          business.update! trial_completion_status: :no_trial_or_active_trial, trial_conversion_initiated_at: nil
        end
        restore_advanced_security_upgrade_state(business)
        business.disable_automatic_self_serve_payment(User.ghost)
      end
      business.owners.each do |owner|
        BusinessMailer.unsuccessful_enterprise_trial_upgrade(owner, business).deliver_later
      end
      business.instrument :restore_trial_state
    end
  end

  def restore_advanced_security_upgrade_state(business)
    return unless business.has_active_advanced_security_subscription?
    return if business.has_active_advanced_security_trial?

    business.cancel_advanced_security_subscription(actor: User.ghost, force: true, skip_sync: true)
  end

  def restore_organization_upgrade_state
    Business.upgrade_purchase_initiated.where(
      "upgrade_purchase_initiated_at < ?", 1.day.ago
    ).find_each do |business|
      with_write do
        if business.organization_upgrade_purchase_initiated?
          business.initiate_organization_upgrade(business.owners.first)
          business.update! upgrade_purchase_initiated_at: nil
        end

        business.disable_automatic_self_serve_payment(User.ghost)
      end

      business.owners.each do |owner|
        BusinessMailer.purchased_org_upgrade_payment_failure(owner, business).deliver_later
      end
    end
  end

  def restore_created_from_coupon_state
    Business.creation_from_coupon_purchase_initiated.where(
      "upgrade_purchase_initiated_at < ?", 1.day.ago
    ).find_each do |business|
      with_write do
        business.reset_coupon_purchase_status
      end
    end
  end
end
