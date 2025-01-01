# typed: true
# frozen_string_literal: true

require "test_helper"

class CopilotOrganizationTest < GitHub::TestCase
  setup do
    GitHub.flipper[:copilot_mixed_licenses].enable
  end

  context "#initialize" do
    test "only allows organization" do
      assert_raises(TypeError) { Copilot::Organization.new(create(:user)) }
    end
  end

  context "billing_summary" do
    test "counts the SEATS we have here" do
      seat = create(:copilot_seat)
      organization = seat.organization
      user = create(:user)
      organization.add_member(user)

      # do not convert to seats
      seat_assignment = create(:copilot_seat_assignment, :user, assignable: user, organization: organization)
      assert seat_assignment.includes_user?(user)
      copilot_organization = Copilot::Organization.new(organization)

      assert_equal 1, copilot_organization.billing_summary[:seats]
      assert_equal 1, copilot_organization.billing_summary[:seats_added] # the seat assignment above hasn't converted so it isn't counted
      assert_equal 0, copilot_organization.billing_summary[:seats_to_be_removed]

      seat_assignment.convert_to_seats

      copilot_organization = Copilot::Organization.new(organization)
      assert_equal 2, copilot_organization.billing_summary[:seats]
      assert_equal 2, copilot_organization.billing_summary[:seats_added]
      assert_equal 0, copilot_organization.billing_summary[:seats_to_be_removed]

      seat.seat_assignment.unassign!(organization.admins.first)

      copilot_organization = Copilot::Organization.new(organization)
      assert_equal 2, copilot_organization.billing_summary[:seats]
      assert_equal 2, copilot_organization.billing_summary[:seats_added]
      assert_equal 1, copilot_organization.billing_summary[:seats_to_be_removed]

      seat_assignment.unassign!(organization.admins.first)

      copilot_organization = Copilot::Organization.new(organization)
      assert_equal 2, copilot_organization.billing_summary[:seats]
      assert_equal 2, copilot_organization.billing_summary[:seats_added]
      assert_equal 2, copilot_organization.billing_summary[:seats_to_be_removed]
    end
  end

  context "on_free_trial?" do
    test "returns true if the organization is on an active business trial" do
      trial = create(:copilot_business_trial, :active, :organization)

      assert Copilot::Organization.new(trial.trialable).on_free_trial?
    end

    test "returns false if the organization is not on a free trial" do
      organization = create(:organization)

      refute Copilot::Organization.new(organization).on_free_trial?
    end
  end

  context "has_seat_for?" do
    test "returns true if the org user has a seat assigned to Copilot" do
      seat = create(:copilot_seat)
      user = create(:user)
      organization = seat.organization
      organization.add_member(user)

      seat_assignment = create(:copilot_seat_assignment, :user, assignable: user, organization: organization)
      seat_assignment.convert_to_seats

      assert Copilot::Organization.new(organization).has_seat_for?(user)
    end

    test "returns false if the organization is not on a free trial" do
      seat = create(:copilot_seat)
      user = create(:user)
      organization = seat.organization

      refute Copilot::Organization.new(organization).has_seat_for?(user)
    end
  end

  context "has_assigned_seats?" do
    test "returns true if the organization has assigned seats" do
      seat = create(:copilot_seat)
      organization = seat.organization

      assert Copilot::Organization.new(organization).has_assigned_seats?
    end

    test "returns false if the organization does not have assigned seats" do
      organization = create(:organization)

      refute Copilot::Organization.new(organization).has_assigned_seats?
    end
  end

  context "#block_if_sharing_payment_method_with_other_blocked_users!" do
    test "blocks the org and returns true if they are sharing payment methods with two or more blocked users" do
      GitHub.flipper[:copilot_block_shared_payment_methods].enable

      org = create(:credit_card_organization)
      blocked_user = create(:credit_card_user)
      blocked_user.customer.payment_method.update(card_fingerprint: org.customer.payment_method.card_fingerprint)
      other_blocked_user = create(:credit_card_user)
      other_blocked_user.customer.payment_method.update(card_fingerprint: org.customer.payment_method.card_fingerprint)

      Copilot::User.new(blocked_user).administrative_block!(create(:user), "reason")
      Copilot::User.new(other_blocked_user).administrative_block!(create(:user), "reason")

      assert Copilot::User.new(org).block_if_sharing_payment_method_with_other_blocked_users!

      assert Copilot::User.new(org.admins.first).administrative_blocked?
    end

    test "blocks the org and returns true if they are sharing payment methods with one blocked user and they are not trusted" do
      GitHub.flipper[:copilot_block_shared_payment_methods].enable

      org = create(:credit_card_organization)
      blocked_user = create(:credit_card_user)
      blocked_user.customer.payment_method.update(card_fingerprint: org.customer.payment_method.card_fingerprint)

      Copilot::User.new(blocked_user).administrative_block!(create(:user), "reason")

      org.settings.set!(:trust_tier, "2")
      assert TrustTiers::Tier.for_billable_owner(org).tier == TrustTiers::Tier::NEUTRAL

      assert Copilot::User.new(org).block_if_sharing_payment_method_with_other_blocked_users!

      assert Copilot::User.new(org.admins.first).administrative_blocked?
    end

    test "doesn't block the org if they're sharing a payment method with one or more blocked users and they're trusted" do
      GitHub.flipper[:copilot_block_shared_payment_methods].enable

      org = create(:credit_card_organization)

      refute Copilot::User.new(org).block_if_sharing_payment_method_with_other_blocked_users!
      refute Copilot::User.new(org.admins.first).administrative_blocked?

      blocked_user = create(:credit_card_user)
      blocked_user.customer.payment_method.update(card_fingerprint: org.customer.payment_method.card_fingerprint)

      Copilot::User.new(blocked_user).administrative_block!(create(:user), "reason")

      org.settings.set!(:trust_tier, "1")
      assert TrustTiers::Tier.for_billable_owner(org).tier == TrustTiers::Tier::TRUSTED

      refute Copilot::User.new(org).block_if_sharing_payment_method_with_other_blocked_users!
      refute Copilot::User.new(org.admins.first).administrative_blocked?
    end
  end

  context "#new_plan_matches_business_plan?" do
    test "returns a boolean indicating is the supplied plan is equal to the existing plan supplied by a parent business" do
      org = create(:copilot_for_business_enabled_organization)
      Copilot::Business.new(org.business).copilot_plan_business!

      refute Copilot::Organization.new(org).new_plan_matches_business_plan?("enterprise")
      assert Copilot::Organization.new(org).new_plan_matches_business_plan?("business")
    end

    test "returns false if the org has no parent business" do
      org = create(:copilot_for_business_enabled_non_enterprise_organization)

      refute Copilot::Organization.new(org).new_plan_matches_business_plan?("enterprise")
      refute Copilot::Organization.new(org).new_plan_matches_business_plan?("business")
    end
  end

  context "#is_copilot_plan_misconfigured?" do
    test "returns true if Copilot is enabled, but the copilot_plan is unconfigured" do
      org = create(:copilot_for_business_enabled_organization)
      Copilot::Organization.new(org).enable_copilot!

      assert Copilot::Organization.new(org).is_copilot_plan_misconfigured?
    end

    test "returns true if copilot is enable and plan is unconfigured, even if business has a plan" do
      org = create(:copilot_for_business_enabled_organization)
      Copilot::Organization.new(org).enable_copilot!
      Copilot::Business.new(org.business).copilot_plan_business!

      assert Copilot::Organization.new(org).is_copilot_plan_misconfigured?
    end

    test "returns false if Copilot is enabled, and the copilot_plan is configured" do
      org = create(:copilot_for_business_enabled_organization)
      copilot_org = Copilot::Organization.new(org)
      copilot_org.enable_copilot!
      copilot_org.copilot_plan_business!

      refute copilot_org.is_copilot_plan_misconfigured?
    end

    test "returns false if Copilot is disabled, and a plan is configured" do
      org = create(:copilot_for_business_enabled_organization)
      copilot_org = Copilot::Organization.new(org)
      copilot_org.disable_copilot!
      copilot_org.copilot_plan_business!

      refute copilot_org.is_copilot_plan_misconfigured?
    end

    test "returns false if the copilot_plan is not unconfigured and copilot is not enabled" do
      org = create(:copilot_for_business_enabled_organization)
      copilot_org = Copilot::Organization.new(org)
      copilot_org.copilot_plan_business!
      copilot_org.disable_copilot!

      refute Copilot::Organization.new(org).is_copilot_plan_misconfigured?
    end

    test "returns false if org is standalone" do
      org = create(:copilot_for_business_enabled_non_enterprise_organization)
      refute Copilot::Organization.new(org).is_copilot_plan_misconfigured?
    end
  end

  context "#is_explicit_plan_confirmation?" do
    context "when the org is standalone" do
      test "returns false" do
        org = create(:copilot_for_business_enabled_non_enterprise_organization)
        refute Copilot::Organization.new(org).is_explicit_plan_confirmation?("enterprise")
      end
    end

    context "when the plan matches the parent business plan" do
      test "returns true if org plan is misconfigured" do
        org = create(:copilot_for_business_enabled_organization)
        cp_biz = Copilot::Business.new(org.business)
        cp_biz.enable_copilot_for_all_organizations!
        cp_biz.copilot_plan_business!

        assert Copilot::Organization.new(org).is_explicit_plan_confirmation?("business")
      end

      test "returns false if org plan is configured" do
        org = create(:copilot_for_business_enabled_organization)

        cp_biz = Copilot::Business.new(org.business)
        cp_org = Copilot::Organization.new(org)

        cp_biz.enable_copilot_for_all_organizations!
        cp_biz.copilot_plan_business!
        cp_org.copilot_plan_business!

        refute cp_org.is_explicit_plan_confirmation?("business")
      end
    end

    context "when the plan does not match the parent business plan" do
      test "returns false if org plan is misconfigured" do
        org = create(:copilot_for_business_enabled_organization)
        cp_biz = Copilot::Business.new(org.business)
        cp_biz.enable_copilot_for_all_organizations!
        cp_biz.copilot_plan_enterprise!

        refute Copilot::Organization.new(org).is_explicit_plan_confirmation?("business")
      end

      test "returns false if org plan is configured" do
        org = create(:copilot_for_business_enabled_organization)

        cp_biz = Copilot::Business.new(org.business)
        cp_org = Copilot::Organization.new(org)

        cp_biz.enable_copilot_for_all_organizations!
        cp_biz.copilot_plan_business!
        cp_org.copilot_plan_business!

        refute cp_org.is_explicit_plan_confirmation?("business")
      end
    end
  end
end if GitHub.copilot_enabled?
