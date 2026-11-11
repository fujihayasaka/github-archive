# typed: true
# frozen_string_literal: true

class CancelTrialBusinessOrchestration < BusinessOrchestration
  step :update_trial_status, transaction: true do
    business = T.must(self.business)

    # Store some values for use later before trial status is updated
    data[:business_owner_ids] = business.owners.pluck(:id)
    data[:trial_expired] = business.trial_expired?
    data[:expiration_timestamp] = business.trial_expires_at.to_s

    # Observability: capture business state before trial cancellation changes anything.
    #
    # See: https://github.com/github/security-products-enablement/issues/2494
    begin
      if FeatureFlag.vexi.enabled?("free_org_ghas_leak_observability", default: false)
        has_dfd_trial = business.dfd_trial?
        has_ghas_trial = business.has_active_advanced_security_trial?
        org_count = business.organizations_limit_counter

        GitHub.dogstats.increment(
          "free_org_ghas_leak_observability.business_trial_cancelled",
          tags: [
            "has_dfd_trial:#{has_dfd_trial}",
            "has_ghas_trial:#{has_ghas_trial}",
          ]
        )
        GitHub.dogstats.distribution(
          "free_org_ghas_leak_observability.business_trial_cancelled.org_count",
          org_count,
          tags: [
            "has_dfd_trial:#{has_dfd_trial}",
            "has_ghas_trial:#{has_ghas_trial}",
          ]
        )
        GitHub.logger.info(
          "free_org_ghas_leak_observability.business_trial_cancelled",
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

    with_write do
      business.touch(:trial_completed_at)
      business.trial_cancelled!
      business.downgrade_to_free_plan
      business.update(trial_expires_at: nil)

      if business.metered_ghe?
        T.must(business.customer).update(azure_subscription_id: nil, azure_subscription_name: nil)
      end
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
    if T.must(business).has_active_advanced_security_trial? && actor.present?
      with_write { T.must(business).end_advanced_security_trial(actor: T.must(actor)) }
    end
  end

  step :enqueue_trial_cancellation_cleanup_job do
    BusinessTrialCancellationCleanupJob.perform_later(T.must(business))
  end

  step :enqueue_security_configuration_cleanup_job do
    enqueue_security_configuration_cleanup
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
