# typed: strict
# frozen_string_literal: true

require "test_helper"

class CopilotBusinessesLicensingTest < GitHub::TestCase
  include CopilotTestHelper # automatically disables Copilot feature flags

  setup do
    @business = T.let(create(:business), T.nilable(::Business))

    # This allows for mixed licenses within the business
    T.must(@business).enable_feature(:copilot_mixed_licenses)

    @cb_org = T.let(create(:organization, business: @business), T.nilable(::Organization))
    @ce_org = T.let(create(:organization, business: @business), T.nilable(::Organization))

    Copilot::Organization.new(T.must(@cb_org)).copilot_plan_business!
    Copilot::Organization.new(T.must(@ce_org)).copilot_plan_enterprise!

    @ce_trial_org = T.let(create(:copilot_for_business_credit_card_enabled_organization, business: @business), T.nilable(::Organization))
    create(:billing_sales_serve_plan_subscription, customer: T.must(@business).customer)
    create(:copilot_business_trial,
      trialable_type: "Organization",
      trialable_id: T.must(@ce_trial_org).id,
      copilot_plan: "enterprise"
    )

    @cb_trial_org = T.let(create(:copilot_for_business_credit_card_enabled_organization, business: @business), T.nilable(::Organization))
    create(:copilot_business_trial, trialable_type: "Organization", trialable_id: T.must(@cb_trial_org).id)
  end

  context "#seats_sorted_by_copilot_sku_by_org_id" do
    test "sorts copilot business trial > copilot enterprise trial > copilot_enterprise > copilot_for_business" do
      cb_seat = create(:copilot_seat, organization: @cb_org)
      cb_seat_2 = create(:copilot_seat, organization: @cb_org)

      ce_seat = create(:copilot_seat, organization: @ce_org, copilot_plan: "enterprise")
      ce_seat_2 = create(:copilot_seat, organization: @ce_org, copilot_plan: "enterprise")

      ce_trial_seat = create(:copilot_seat, organization: @ce_trial_org)
      cb_trial_seat = create(:copilot_seat, organization: @cb_trial_org)

      cb_org_id = T.must(@cb_org).id
      ce_org_id = T.must(@ce_org).id
      cb_trial_org_id = T.must(@cb_trial_org).id
      ce_trial_org_id = T.must(@ce_trial_org).id

      sorted_result = Copilot::Business.new(T.must(@business).reload).seats_sorted_by_copilot_sku_by_org_id

      assert_equal [cb_trial_org_id, ce_trial_org_id, ce_org_id, cb_org_id], sorted_result.keys

      assert_equal sorted_result[T.must(ce_trial_org_id)], [ce_trial_seat.assigned_user_id]
      assert_equal sorted_result[T.must(cb_trial_org_id)], [cb_trial_seat.assigned_user_id]

      assert_includes sorted_result[T.must(cb_org_id)], cb_seat.assigned_user_id
      assert_includes sorted_result[T.must(cb_org_id)], cb_seat_2.assigned_user_id
      assert_includes sorted_result[T.must(ce_org_id)], ce_seat.assigned_user_id
      assert_includes sorted_result[T.must(ce_org_id)], ce_seat_2.assigned_user_id
    end

    test "sorts :COPILOT_FOR_BUSINESS_BILLING_LOCKED towards the end" do
      cb_seat = create(:copilot_seat, organization: @cb_org)
      ce_seat = create(:copilot_seat, organization: @ce_org, copilot_plan: "enterprise")

      copilot_billing_locked_org = create(:copilot_for_business_enabled_organization, business: @business)
      copilot_billing_locked_seat = create(:copilot_seat, organization: copilot_billing_locked_org)
      copilot_billing_locked_seat.owner.disable!

      cb_org_id = T.must(@cb_org).id
      ce_org_id = T.must(@ce_org).id
      copilot_billing_locked_org_id = copilot_billing_locked_org.id

      sorted_result = Copilot::Business.new(T.must(@business).reload).seats_sorted_by_copilot_sku_by_org_id

      assert_equal [ce_org_id, cb_org_id, copilot_billing_locked_org_id], sorted_result.keys

      assert_equal sorted_result[T.must(cb_org_id)], [cb_seat.assigned_user_id]
      assert_equal sorted_result[T.must(ce_org_id)], [ce_seat.assigned_user_id]
      assert_equal sorted_result[copilot_billing_locked_org_id], [copilot_billing_locked_seat.assigned_user_id]
    end
  end

  context "#copilot_enabled_members_count_by_license" do
    test "counts distinct members across all orgs bucketed by license" do
      business = create(:business)
      business.enable_feature(:copilot_mixed_licenses)
      org1 = create(:organization, business: business)
      org2 = create(:organization, business: business)
      user1 = create(:user)
      org1.add_member(user1)
      org2.add_member(user1)
      create(:copilot_seat_assignment, organization: org1, assignable: user1).convert_to_seats
      create(:copilot_seat_assignment, organization: org2, assignable: user1).convert_to_seats

      Copilot::Organization.new(org1).copilot_plan_enterprise!
      Copilot::Organization.new(org2).copilot_plan_business!
      copilot_business = Copilot::Business.new(business.reload)
      users_by_plan = copilot_business.copilot_enabled_members_count_by_license

      # user1 has a seat in both orgs, but they should only count as one member, in org 1, the higher-priced seat
      assert_equal 1, users_by_plan[:enterprise]
      assert_equal 0, users_by_plan[:business]
    end

    test "dedupes and buckets correctly when there are only business seats" do
      business = create(:business)
      business.enable_feature(:copilot_mixed_licenses)
      org1 = create(:organization, business: business)
      org2 = create(:organization, business: business)
      user1 = create(:user)
      org1.add_member(user1)
      org2.add_member(user1)
      create(:copilot_seat_assignment, organization: org1, assignable: user1).convert_to_seats
      create(:copilot_seat_assignment, organization: org2, assignable: user1).convert_to_seats

      Copilot::Organization.new(org1).copilot_plan_business!
      Copilot::Organization.new(org2).copilot_plan_business!
      copilot_business = Copilot::Business.new(business.reload)

      users_by_plan = copilot_business.copilot_enabled_members_count_by_license
      assert_equal 0, users_by_plan[:enterprise]
      assert_equal 1, users_by_plan[:business]
    end

    test "properly buckets trial seats as business seats when org has enterprise plan" do
      Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)

      business = create(:business)
      business.enable_feature(:copilot_mixed_licenses)

      org1 = create(:organization, business: business)
      org2 = create(:organization, business: business)
      user1 = create(:user)
      user2 = create(:user)
      org1.add_member(user1)
      org1.add_member(user2)
      org2.add_member(user1)

      Copilot::Business.new(business).copilot_plan_business!
      Copilot::Organization.new(org1).copilot_plan_enterprise!
      Copilot::Organization.new(org2).copilot_plan_business!

      create(:copilot_business_trial, trialable_type: "Organization", trialable_id: org1.id, copilot_plan: "enterprise")

      create(:copilot_seat_assignment, organization: org1, assignable: user1).convert_to_seats
      create(:copilot_seat_assignment, organization: org1, assignable: user2).convert_to_seats
      create(:copilot_seat_assignment, organization: org2, assignable: user1).convert_to_seats

      Copilot::Organization.new(org1).copilot_plan_enterprise!
      Copilot::Organization.new(org2).copilot_plan_business!
      copilot_business = Copilot::Business.new(business.reload)

      users_by_plan = copilot_business.copilot_enabled_members_count_by_license

      assert_equal 0, users_by_plan[:enterprise]
      assert_equal 2, users_by_plan[:business]
    end

    test "omits business trial seats from buckets" do
      Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)

      business = create(:business)
      business.enable_feature(:copilot_mixed_licenses)

      org1 = create(:organization, business: business)
      org2 = create(:organization, business: business)
      org3 = create(:organization, business: business)
      create(:copilot_business_trial, trialable_type: "Organization", trialable_id: org3.id, copilot_plan: "business")

      user1 = create(:user)
      user2 = create(:user)

      # Org 1 will have an enterprise license
      org1.add_member(user1)
      org1.add_member(user2)
      # Org two has an enterprise trial
      org2.add_member(user1)
      # Org 3 has a business trial
      org3.add_member(user1)

      # Seats should be considered for billing like Trial > Enterprise > Business

      Copilot::Business.new(business).copilot_plan_business!
      Copilot::Organization.new(org1).copilot_plan_enterprise!
      Copilot::Organization.new(org2).copilot_plan_business!

      create(:copilot_business_trial, trialable_type: "Organization", trialable_id: org1.id, copilot_plan: "enterprise")

      create(:copilot_seat_assignment, organization: org1, assignable: user1).convert_to_seats
      create(:copilot_seat_assignment, organization: org1, assignable: user2).convert_to_seats
      create(:copilot_seat_assignment, organization: org2, assignable: user1).convert_to_seats
      create(:copilot_seat_assignment, organization: org3, assignable: user1).convert_to_seats

      Copilot::Organization.new(org1).copilot_plan_enterprise!
      Copilot::Organization.new(org2).copilot_plan_business!
      copilot_business = Copilot::Business.new(business.reload)

      users_by_plan = copilot_business.copilot_enabled_members_count_by_license

      assert_equal 0, users_by_plan[:enterprise]
      assert_equal 1, users_by_plan[:business]
    end
  end
end if GitHub.copilot_enabled?
