# typed: true
# frozen_string_literal: true

class ExpireTrialBusinessOrchestration < BusinessOrchestration
  step :update_trial_status, transaction: true do
    # Store some values for use later before trial status is updated
    data[:business_owner_ids] = T.must(business).owners.pluck(:id)
    data[:expiration_timestamp] = T.must(business).trial_expires_at.to_s

    T.must(business).skip_billing_email_not_disposable_validation = true

    T.must(business).touch(:trial_completed_at)
    T.must(business).trial_expired!
    T.must(business).downgrade_to_free_plan
    if T.must(business).trial_expires_at > Time.current
      T.must(business).update(trial_expires_at: 1.second.ago)
    end
    if T.must(business).eligible_for_expired_trial_deletion?
      T.must(business).update(trial_deleted_at: 90.days.from_now)
    end
  end

  step :instrument do
    GlobalInstrumenter.instrument("enterprise_account.trial", {
      enterprise: T.must(business),
      actor: actor,
      user_initiated: actor ? :STAFF : :AUTOMATION,
      status: :EXPIRED,
      expiration_timestamp: Time.zone.parse(data[:expiration_timestamp]),
      upgraded_organization: T.must(business).upgraded_from,
      metered: T.must(business).metered_plan?,
      emu: T.must(business).enterprise_managed_user_enabled?
    })
    GlobalInstrumenter.instrument("enterprise_account.salesforce_trial_update", {
      enterprise: T.must(business),
      actor: actor,
      user_initiated: actor ? :STAFF : :AUTOMATION,
      status: :EXPIRED,
      expiration_timestamp: Time.zone.parse(data[:expiration_timestamp]),
      upgraded_organization: T.must(business).upgraded_from,
      metered: T.must(business).metered_plan?,
      emu: T.must(business).enterprise_managed_user_enabled?
    })
    T.must(business).instrument(:expire_trial)
    GitHub.dogstats.increment("business.trial.expire")
  end

  step :remove_organizations do
    invited_organization_ids = T.must(business).organization_invitations.with_status(:confirmed).distinct.pluck(:invitee_id)
    invited_organization_ids.each_slice(Business::DELETE_BATCH_SIZE) do |organization_ids|
      Organization.where(id: organization_ids).find_each do |organization|
        if T.must(business) == organization.business
          T.must(business).remove_organization(organization, permit_removal_of_org_with_no_admins: true)
        end
      end
    end

    T.must(business).reload

    if T.must(business).upgraded_from.present? &&
      T.must(T.must(business).upgraded_from).business_membership.present? &&
      T.must(T.must(business).upgraded_from).business_membership&.business_id == T.must(business).id
      T.must(business).remove_organization(T.must(business).upgraded_from, permit_removal_of_org_with_no_admins: true)
    end

    T.must(business).organization_invitations.where(confirmed_at: nil).destroy_all
  end

  step :end_advanced_security_trial do
    if T.must(business).has_active_advanced_security_trial?
      T.must(business).end_advanced_security_trial_without_purchasing_now(
        actor: T.must(actor),
        billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month
      )
    end
  end

  step :send_email_notification do
    business_owners = User.where(id: data[:business_owner_ids])
    business_owners.each do |owner|
      BusinessMailer.trial_period_ended_for_enterprise_trial_account(
        owner,
        T.must(business)
      ).deliver_later
    end
  end
end
