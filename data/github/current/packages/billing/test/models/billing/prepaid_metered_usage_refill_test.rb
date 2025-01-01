# typed: true
# frozen_string_literal: true

require "test_helper"

class BillingPrepaidMeteredUsageRefillTest < GitHub::TestCase
  context ".enabled_for?" do
    test "false for users" do
      user = create(:user)

      refute Billing::PrepaidMeteredUsageRefill.enabled_for?(user)
    end

    test "false for enterprise accounts with active enterprise agreements" do
      business = create(:business, :volume_licensed)
      refute Billing::PrepaidMeteredUsageRefill.enabled_for?(business)
    end

    test "true for enterprise accounts without active enterprise agreements" do
      business = create(:business)
      assert Billing::PrepaidMeteredUsageRefill.enabled_for?(business)
    end

    test "false for non-invoiced organizations" do
      organization = create(:credit_card_organization)
      refute Billing::PrepaidMeteredUsageRefill.enabled_for?(organization)
    end

    test "false for business-owned organizations" do
      business = create(:business)
      organization = create(:invoiced_organization, business: business)
      refute Billing::PrepaidMeteredUsageRefill.enabled_for?(organization)
    end

    test "true for invoiced organizations that are not owned by a business" do
      organization = create(:invoiced_organization)
      assert Billing::PrepaidMeteredUsageRefill.enabled_for?(organization)
    end
  end

  context ".total_active_amount_in_cents_for" do
    test "returns the sum of the active refills" do
      owner = create(:business)

      create(:billing_prepaid_metered_usage_refill, owner: owner, amount_in_subunits: 50_00, expires_on: 1.year.ago)
      create(:billing_prepaid_metered_usage_refill, owner: owner, amount_in_subunits: 100_00, expires_on: 1.year.from_now)
      create(:billing_prepaid_metered_usage_refill, owner: owner, amount_in_subunits: 200_00, expires_on: 1.year.from_now)

      assert_equal 350_00, Billing::PrepaidMeteredUsageRefill.total_active_amount_in_cents_for(owner: owner)
    end
  end

  context "#staff_created?" do
    test "returns true when there's no Zuora rate plan charge ID" do
      refill = Billing::PrepaidMeteredUsageRefill.new(zuora_rate_plan_charge_id: nil)

      assert refill.staff_created?
    end

    test "returns false when there is a Zuora rate plan charge ID" do
      refill = Billing::PrepaidMeteredUsageRefill.new(zuora_rate_plan_charge_id: "something")

      refute refill.staff_created?
    end
  end

  context "audit log" do
    test "instruments create event on create" do
      events = subscribe("prepaid_metered_refill.create")

      owner = create(:business)
      create(
        :billing_prepaid_metered_usage_refill,
        owner: owner,
        amount_in_subunits: 50_00,
        expires_on: 1.year.ago,
        zuora_rate_plan_charge_id: nil,
      )

      expected_event = {
        amount_in_subunits: 50_00,
        currency_code: "USD",
        expires_on: 1.year.ago.to_date,
        staff_created: true,
        business: owner.slug,
        business_id: owner.id,
      }

      assert_equal expected_event, events.pop.payload
    end

    test "instruments create event on create works for organizations" do
      events = subscribe("prepaid_metered_refill.create")

      owner = create(:organization)
      create(
        :billing_prepaid_metered_usage_refill,
        owner: owner,
        amount_in_subunits: 50_00,
        expires_on: 1.year.ago,
        zuora_rate_plan_charge_id: SecureRandom.hex,
      )

      expected_event = {
        amount_in_subunits: 50_00,
        currency_code: "USD",
        expires_on: 1.year.ago.to_date,
        staff_created: false,
        org: owner.name,
        org_id: owner.id,
      }

      assert_equal expected_event, events.pop.payload
    end
  end
end if GitHub.billing_enabled?
