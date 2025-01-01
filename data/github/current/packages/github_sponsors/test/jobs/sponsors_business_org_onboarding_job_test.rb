# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsBusinessOrgOnboardingJobTest < GitHub::TestCase

  fixtures do
    @owner = create(:user)
    @upgrading_business = create(
      :business, owners: [@owner]
    )
    @upgrading_business.customer.update(billing_type: ::Customer::BILLING_TYPE_CARD)
    @upgrading_org = create(:organization, business: @upgrading_business, admins: [@owner])

    @upgrading_invoice_business = create(
      :business, owners: [@owner]
    )
    @upgrading_invoice_business.customer.update(billing_type: ::Customer::BILLING_TYPE_INVOICE)
    @upgrading_invoice_org = create(:organization, business: @upgrading_invoice_business, admins: [@owner])
  end

  test "grants upgraded org sponsorship permission" do
    assert_equal @upgrading_business, @upgrading_org.business
    refute @upgrading_org.has_sponsorships_access?

    SponsorsBusinessOrgOnboardingJob.perform_now(
      organization: @upgrading_org, actor: @owner
    )

    assert @upgrading_org.reload.has_sponsorships_access?
  end

  test "does not grant sponsorship permission when enterprise is in trial" do
    @upgrading_business.update_attribute(:trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now)

    assert_equal @upgrading_business, @upgrading_org.business
    refute @upgrading_org.has_sponsorships_access?

    SponsorsBusinessOrgOnboardingJob.perform_now(
      organization: @upgrading_org, actor: @owner
    )

    refute @upgrading_org.reload.has_sponsorships_access?
  end

  test "does not grant sponsorship permission when actor is missing" do
    assert_equal @upgrading_business, @upgrading_org.business
    refute @upgrading_org.has_sponsorships_access?

    SponsorsBusinessOrgOnboardingJob.perform_now(
      organization: @upgrading_org, actor: nil
    )

    refute @upgrading_org.reload.has_sponsorships_access?
  end

  test "does not grant sponsorship permission when business is not self serve" do
    assert_equal @upgrading_invoice_business, @upgrading_invoice_org.business
    refute @upgrading_invoice_org.has_sponsorships_access?

    SponsorsBusinessOrgOnboardingJob.perform_now(
      organization: @upgrading_invoice_org, actor: @owner
    )

    refute @upgrading_invoice_org.reload.has_sponsorships_access?
  end
end if GitHub.sponsors_enabled?
