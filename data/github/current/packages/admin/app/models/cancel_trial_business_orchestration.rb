# typed: true
# frozen_string_literal: true

class CancelTrialBusinessOrchestration < BusinessOrchestration
  step :update_trial_status, transaction: true do
    # Store some values for use later before trial status is updated
    data[:business_owner_ids] = T.must(business).owners.pluck(:id)
    data[:trial_expired] = T.must(business).trial_expired?
    data[:expiration_timestamp] = T.must(business).trial_expires_at.to_s

    T.must(business).touch(:trial_completed_at)
    T.must(business).trial_cancelled!
    T.must(business).downgrade_to_free_plan
    T.must(business).update(trial_expires_at: nil)

    if T.must(business).metered_ghe?
      T.must(T.must(business).customer).update(azure_subscription_id: nil, azure_subscription_name: nil)
    end
  end

  step :instrument do
    GlobalInstrumenter.instrument("enterprise_account.trial", {
      enterprise: T.must(business),
      actor: actor,
      user_initiated: data[:staff_initiated] ? :STAFF : :USER,
      status: :CANCELLED,
      expiration_timestamp: Time.zone.parse(data[:expiration_timestamp]),
      upgraded_organization: T.must(business).upgraded_from,
      metered: T.must(business).metered_plan?,
      emu: T.must(business).enterprise_managed_user_enabled?
    })
    GlobalInstrumenter.instrument("enterprise_account.salesforce_trial_update", {
      enterprise: T.must(business),
      actor: actor,
      user_initiated: data[:staff_initiated] ? :STAFF : :USER,
      status: :CANCELLED,
      expiration_timestamp: Time.zone.parse(data[:expiration_timestamp]),
      upgraded_organization: T.must(business).upgraded_from,
      metered: T.must(business).metered_plan?,
      emu: T.must(business).enterprise_managed_user_enabled?
    })
    T.must(business).instrument(:cancel_trial)
    GitHub.dogstats.increment("business.trial.cancel")
  end

  step :end_advanced_security_trial do
    if T.must(business).has_active_advanced_security_trial?
      T.must(business).end_advanced_security_trial_without_purchasing_now(
        actor: T.must(actor),
        billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month
      )
    end
  end

  step :enqueue_trial_cancellation_cleanup_job do
    BusinessTrialCancellationCleanupJob.perform_later(T.must(business))
  end

  step :send_email_notification do
    business_owners = User.where(id: data[:business_owner_ids])
    business_owners.each do |owner|
      BusinessMailer.cancel_trial_for_enterprise_trial_account(
        owner,
        T.must(business),
        data[:trial_expired]
      ).deliver_later
    end
  end
end
