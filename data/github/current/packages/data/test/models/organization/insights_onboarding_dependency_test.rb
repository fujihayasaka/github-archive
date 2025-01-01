# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationInsightsDependencyTest < GitHub::TestCase
  include HydroTestHelpers

  context "does not publish a billing plan change message" do
    test "when a free org is created" do
      org = create(:free_organization)

      assert_hydro_messages(count: 0, schema: "github.v1.BillingPlanChange")
    end
    test "when a free org is deleted" do
      org = create(:free_organization)
      org.destroy!

      assert_hydro_messages(count: 0, schema: "github.v1.BillingPlanChange")
    end
  end

  context "publishes a billing plan change message" do
    test "when a paid org is created" do
      org = create(:business_organization)

      expected_message = {
        user: org.login,
        previous_plan: nil,
        current_plan: GitHub::Plan::BUSINESS,
        action: :UPGRADE,
        organization: Hydro::EntitySerializer.organization(org),
      }

      assert_hydro_published(expected_message, schema: "github.v1.BillingPlanChange", count: 1)
    end

    test "when an organization upgrades plans" do
      org = create(:free_organization)
      org.update(plan: GitHub::Plan.business)

      expected_message = {
        user: org.login,
        previous_plan: GitHub::Plan::FREE,
        current_plan: GitHub::Plan::BUSINESS,
        action: :UPGRADE,
        organization: Hydro::EntitySerializer.organization(org),
      }

      assert_hydro_published(expected_message, schema: "github.v1.BillingPlanChange", count: 1)
    end

    test "when an organization downgrades plans" do
      org = create(:business_organization)
      org.update(plan: GitHub::Plan.free)

      expected_message = {
        user: org.login,
        previous_plan: GitHub::Plan::BUSINESS,
        current_plan: GitHub::Plan::FREE,
        action: :DOWNGRADE,
        organization: Hydro::EntitySerializer.organization(org),
      }

      assert_hydro_published(expected_message, schema: "github.v1.BillingPlanChange", count: 1)
    end

    test "when an org redeems a coupon" do
      org = create(:free_organization)
      coupon = create(:coupon, plan: GitHub::Plan.business_plus, discount: 1.0)
      org.redeem_coupon(coupon)

      expected_message = {
        user: org.login,
        previous_plan: GitHub::Plan::FREE,
        current_plan: GitHub::Plan::BUSINESS_PLUS,
        action: :UPGRADE,
        organization: Hydro::EntitySerializer.organization(org),
      }

      assert_hydro_published(expected_message, schema: "github.v1.BillingPlanChange", count: 1)
    end

    test "when an org signs up for a trial plan" do
      org = create(:free_organization)
      assert Billing::EnterpriseCloudTrial.new(org).create

      expected_message = {
        user: org.login,
        previous_plan: GitHub::Plan::FREE,
        current_plan: GitHub::Plan::BUSINESS_PLUS,
        action: :UPGRADE,
        organization: Hydro::EntitySerializer.organization(org),
      }

      assert_hydro_published(expected_message, schema: "github.v1.BillingPlanChange", count: 1)
    end

    test "when there is a change in an org's trial plan" do
      org = create(:business_organization, seats: 20)
      Billing::EnterpriseCloudTrial.new(org).create
      org.pending_plan_changes.last.run

      expected_message = {
        user: org.login,
        previous_plan: GitHub::Plan::BUSINESS_PLUS,
        current_plan: GitHub::Plan::BUSINESS,
        action: :UPGRADE,
        organization: Hydro::EntitySerializer.organization(org),
      }

      assert_hydro_published(expected_message, schema: "github.v1.BillingPlanChange", count: 1)
    end
  end
  test "when an organization is deleted" do
    org = create(:business_organization)

    expected_created_message = {
      user: org.login,
      previous_plan: nil,
      current_plan: GitHub::Plan::BUSINESS,
      action: :UPGRADE,
      organization: Hydro::EntitySerializer.organization(org),
    }
    expected_deleted_message = {
      user: org.login,
      previous_plan: GitHub::Plan::BUSINESS,
      current_plan: "",
      action: :DOWNGRADE,
      organization: Hydro::EntitySerializer.organization(org),
    }

    assert_hydro_published(expected_created_message, schema: "github.v1.BillingPlanChange", count: 1)

    org.destroy!
    assert_hydro_published(expected_deleted_message, schema: "github.v1.BillingPlanChange", count: 1)
  end
end
