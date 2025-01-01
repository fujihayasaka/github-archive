# typed: true
# frozen_string_literal: true

class ConvertTrialBusinessOrchestration < BusinessOrchestration
  step :update_trial_status, transaction: true do
    T.must(business).touch(:trial_completed_at)
    T.must(business).trial_converted!
    T.must(business).upgrade_to_business_plus_plan if T.must(business).downgraded_to_free_plan?
    if T.must(business).enterprise_managed?
      first_emu_owner = T.must(business).find_first_emu_owner
      first_emu_owner.unsuspend("Trial converted", actor: actor) if first_emu_owner.suspended?
    end

    data[:expiration_timestamp] = T.must(business).trial_expires_at.to_s

    T.must(business).update(trial_expires_at: nil)
    T.must(business).update(trial_deleted_at: nil)
  end

  step :instrument do
    GlobalInstrumenter.instrument("enterprise_account.trial", {
      enterprise: T.must(business),
      actor: actor,
      user_initiated: data[:staff_initiated] ? :STAFF : :USER,
      status: :UPGRADED,
      expiration_timestamp: Time.zone.parse(data[:expiration_timestamp]),
      upgraded_organization: T.must(business).upgraded_from,
      metered: T.must(business).metered_plan?,
      emu: T.must(business).enterprise_managed_user_enabled?
    })
    GlobalInstrumenter.instrument("enterprise_account.salesforce_trial_update", {
      enterprise: T.must(business),
      actor: actor,
      user_initiated: data[:staff_initiated] ? :STAFF : :USER,
      status: :UPGRADED,
      expiration_timestamp: Time.zone.parse(data[:expiration_timestamp]),
      upgraded_organization: T.must(business).upgraded_from,
      metered: T.must(business).metered_plan?,
      emu: T.must(business).enterprise_managed_user_enabled?,
      talk_to_sales: T.must(business).talk_to_sales,
      payment_method: T.must(business).payment_method_enum
    })
    T.must(business).instrument(:convert_trial)
    GitHub.dogstats.increment("business.trial.convert")
  end

  step :send_welcome_net_new_enterprise_account_email do
    T.must(business).send_welcome_net_new_enterprise_account_email
  end

  step :update_billing do
    if data[:switch_billing_to_invoice]
      T.must(business).customer&.update(billing_type: Customer::BILLING_TYPE_INVOICE)
    elsif T.must(business).enable_autopay_on_trial_conversion?
      T.must(business).enable_automatic_self_serve_payment(T.must(actor), reason: :enterprise_purchase)
    end
  end

  step :convert_metered_ghe do
    T.must(business).convert_metered_ghe(actor)
  end

  step :sync_all_organization_billing_settings do
    T.must(business).sync_all_organization_billing_settings(
      enterprise_purchase: true,
      switch_org_billing_to_invoice: data[:switch_billing_to_invoice]
    )
  end

  step :update_license_usage do
    T.must(business).update_license_usage
  end

  step :update_customer_in_licensify do
    UpdateCustomerInLicensifyJob.perform_later(T.must(business).customer_id)
  end

  step :migrate_to_billing_platform do
    Billing::Migration::MigrateMeuseBudgetToBillingPlatformJob.perform_later(
      customer: T.must(T.must(business).customer),
      set_copilot_default_budget_only: true
    )
  end
end
