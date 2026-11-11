# typed: true
# frozen_string_literal: true

class ExpireTrialBusinessOrchestration < BusinessOrchestration
  step :update_trial_status, transaction: true do
    business = T.must(self.business)
    # Store some values for use later before trial status is updated
    data[:business_owner_ids] = business.owners.pluck(:id)
    data[:expiration_timestamp] = business.trial_expires_at.to_s

    # Observability: capture business state before trial expiration changes anything.
    # After downgrade_to_free_plan + remove_organizations, this data is lost.
    #
    # See: https://github.com/github/security-products-enablement/issues/2494
    begin
      if FeatureFlag.vexi.enabled?("free_org_ghas_leak_observability", default: false)
        has_dfd_trial = business.dfd_trial?
        has_ghas_trial = business.has_active_advanced_security_trial?
        org_count = business.organizations_limit_counter

        GitHub.dogstats.increment(
          "free_org_ghas_leak_observability.business_trial_expired",
          tags: [
            "has_dfd_trial:#{has_dfd_trial}",
            "has_ghas_trial:#{has_ghas_trial}",
          ]
        )
        GitHub.dogstats.distribution(
          "free_org_ghas_leak_observability.business_trial_expired.org_count",
          org_count,
          tags: [
            "has_dfd_trial:#{has_dfd_trial}",
            "has_ghas_trial:#{has_ghas_trial}",
          ]
        )
        GitHub.logger.info(
          "free_org_ghas_leak_observability.business_trial_expired",
          "gh.business.id": business.id,
          "gh.business.slug": business.slug,
          "gh.business.has_dfd_trial": has_dfd_trial,
          "gh.business.has_ghas_trial": has_ghas_trial,
          "gh.business.org_count": org_count,
        )
      end
    rescue => error
      Failbot.report(error, context: "free_org_ghas_leak_observability")
    end

    business.skip_billing_email_not_disposable_validation = true

    with_write do
      business.touch(:trial_completed_at)
      business.trial_expired!
      business.downgrade_to_free_plan
      if business.trial_expires_at > Time.current
        business.update(trial_expires_at: 1.second.ago)
      end
      if business.eligible_for_expired_trial_deletion?
        business.update(trial_deleted_at: 90.days.from_now)
      end
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
          with_write { T.must(business).remove_organization(organization, permit_removal_of_org_with_no_admins: true) }
        end
      end
    end

    T.must(business).reload

    if T.must(business).upgraded_from.present? &&
      T.must(T.must(business).upgraded_from).business_membership.present? &&
      T.must(T.must(business).upgraded_from).business_membership&.business_id == T.must(business).id
      with_write { T.must(business).remove_organization(T.must(business).upgraded_from, permit_removal_of_org_with_no_admins: true) }
    end

    with_write { T.must(business).organization_invitations.where(confirmed_at: nil).destroy_all }
  end

  step :end_advanced_security_trial do
    if T.must(business).has_active_advanced_security_trial? && actor.present?
      with_write { T.must(business).end_advanced_security_trial(actor: T.must(actor)) }
    end
  end

  step :enqueue_security_configuration_cleanup_job do
    enqueue_security_configuration_cleanup
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
