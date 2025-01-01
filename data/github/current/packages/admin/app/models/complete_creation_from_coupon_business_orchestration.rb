# typed: true
# frozen_string_literal: true

class CompleteCreationFromCouponBusinessOrchestration < BusinessOrchestration
  job_start

  step :mark_created_from_coupon do
    # Mark as completed since coupon has been redeemed
    T.must(business).created_from_coupon!
  end

  step :attach_organization_for_upgrade do
    if org_to_attach.present? && T.must(business) == org_to_attach.upgrade_to_enterprise_in_progress
      if org_to_attach.adminable_by?(initiating_owner)
        T.must(business).attach_organization_for_upgrade(org_to_attach, initiating_owner)
      end
      org_to_attach.clear_upgrade_to_enterprise_in_progress!
    end
  end

  step :set_customer_to_split_metered_offering do
    T.must(business).set_customer_to_split_metered_offering(actor: T.must(actor))
  end

  step :sync_all_organization_billing_settings do
    T.must(business).sync_all_organization_billing_settings(
      enterprise_purchase: true,
      switch_org_billing_to_invoice: false
    )
  end

  step :instrument do
    T.must(business).instrument_ea_creation_from_coupon_redemption(
      actor,
      :CREATED_FROM_COUPON,
      coupon: T.must(business).coupon&.code
    )
  end

  step :send_email_notification do
    BusinessMailer.creation_from_coupon_success(initiating_owner, T.must(business)).deliver_later
  end

  private

  memoize def org_to_attach
    T.must(business).upgrade_initiated_from_organization
  end

  memoize def initiating_owner
    T.must(business).owners.first
  end
end
