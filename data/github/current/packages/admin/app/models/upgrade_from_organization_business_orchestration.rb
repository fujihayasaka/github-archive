# typed: true
# frozen_string_literal: true

class UpgradeFromOrganizationBusinessOrchestration < BusinessOrchestration
  step :validate_upgrade do
    return :skipped if GitHub.single_business_environment?
    return :skipped if T.must(business).trial?
    return :skipped unless T.must(business).organization_upgrade_purchase_initiated?
  end

  job_start

  step :mark_upgrade_completed do
    # Mark as completed since payment has been processed
    T.must(business).organization_upgrade_completed!
  end

  step :attach_organization_for_upgrade do
    if org_to_attach.present? && T.must(business) == org_to_attach.upgrade_to_enterprise_in_progress
      begin
        if org_to_attach.adminable_by?(initiating_owner)
          T.must(business).attach_organization_for_upgrade(org_to_attach, initiating_owner)
        end
      rescue ActiveRecord::RecordInvalid, Business::CannotAddOrganizationError => e
        # Catch the potential race condition where the organization cannot be attached to the EA
        # if the organization seat count has increased while the payment has been processing.
        BusinessMailer.attach_organization_to_enterprise_failure(initiating_owner, T.must(business)).deliver_later
        initiating_owner.reset_notice("org_attachment_failure")
        EnterpriseAccounts::KV.store.set(
          T.must(business).org_attachment_failure_notice_key(initiating_owner),
          Time.now.utc.iso8601
        )
      end
      # Unmark the organization as in process for upgrade
      org_to_attach.clear_upgrade_to_enterprise_in_progress!
      T.must(business).instrument_organization_upgrade_event(actor, :PURCHASE_UPGRADED)
    end
  end

  step :instrument do
    T.must(business).instrument(:upgrade_from_organization, org: org_to_attach)
  end

  step :enable_automatic_self_serve_payment do
    T.must(business).enable_automatic_self_serve_payment(T.must(actor), reason: :enterprise_purchase)
  end

  step :sync_organization_billing_settings do
    T.must(business).sync_all_organization_billing_settings(
      enterprise_purchase: true,
      switch_org_billing_to_invoice: false
    )
  end

  step :set_org_upgrade_onboarding_notice do
    T.must(business).set_org_upgrade_onboarding_notice(
      initiating_owner: initiating_owner,
      organization: org_to_attach
    )
  end

  step :clear_kv_value do
    EnterpriseAccounts::KV.store.del("organization_upgrade_purchase_initiated/#{T.must(business).id}")
  end

  private

  memoize def org_to_attach
    T.must(business).upgrade_initiated_from_organization
  end

  memoize def initiating_owner
    T.must(business).owners.first
  end
end
