# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationProfileTest < GitHub::TestCase
  context "validations" do
    test "requires an organization" do
      org_profile = OrganizationProfile.new
      refute_predicate org_profile, :valid?
      assert_includes org_profile.errors[:organization], "must exist"
    end

    test "requires a unique organization" do
      org_profile1 = create(:organization_profile)
      org_profile2 = OrganizationProfile.new(organization_id: org_profile1.organization_id)
      refute_predicate org_profile2, :valid?
      assert_includes org_profile2.errors[:organization_id], "has already been taken"
    end

    test "requires Stripe customer ID to be unique if set" do
      org_profile1 = create(:organization_profile, stripe_customer_id: "cus_1234abcd")
      org_profile2 = OrganizationProfile.new(stripe_customer_id: "cus_1234abcd")
      refute_predicate org_profile2, :valid?
      assert_includes org_profile2.errors[:stripe_customer_id], "has already been taken"
    end

    test "allows multiple organization profiles to exist with no Stripe customer ID" do
      org_profile1 = create(:organization_profile, stripe_customer_id: nil)
      org_profile2 = build(:organization_profile, stripe_customer_id: nil)
      assert_predicate org_profile2, :valid?
    end
  end
end
