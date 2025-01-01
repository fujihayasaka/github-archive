# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Platform::Api::BudgetTest < GitHub::TestCase
  include Billing::Platform::Api::Utils

  context "#customer_id" do
    test "returns a string id" do
      budget = build(:budget)

      assert_equal budget.customer_id, 1
    end
  end

  context "#target_type" do
    test "returns a string" do
      budget = build(:budget)

      assert_equal budget.target_type, CUSTOMER_TARGET
    end
  end

  context "#target_id" do
    test "returns a string id" do
      budget = build(:budget)

      assert_equal budget.target_id, "12345"
    end
  end

  context "#global_target_id" do
    test "returns a global ID for Organization" do
      org = create(:organization)
      budget = build(:budget, targetType: :Org, targetId: org.id)
      assert_equal budget.global_target_id, org.global_relay_id
    end

    test "returns a global ID for Repository" do
      repo = create(:repository)
      budget = build(:budget, targetType: :Repo, targetId: repo.id)
      assert_equal budget.global_target_id, repo.global_relay_id
    end

    test "returns the original ID for a Customer" do
      budget = build(:budget, targetType: CUSTOMER_TARGET, targetId: 1)
      assert_equal budget.global_target_id, 1
    end
  end

  context "#pricing_target_type" do
    test "returns a string pricing target type" do
      budget = build(:budget)

      assert_equal budget.pricing_target_type, "SkuPricing"
    end
  end

  context "#pricing_target_id" do
    test "returns a string pricing target id" do
      budget = build(:budget)

      assert_equal budget.pricing_target_id, "sku"
    end
  end

  context "#product_name" do
    test "returns product name based on pricing target" do
      budget = build(:budget)

      assert_equal "billing_platform_SkuPricing", budget.product_name
    end
  end

  context "#target_amount" do
    test "returns a float" do
      budget = build(:budget)

      assert_equal budget.target_amount, 100.0
    end
  end

  context "#budget_limit_type" do
    test "returns a string" do
      budget = build(:budget)

      assert_equal budget.budget_limit_type, "AlertingOnly"
    end
  end

  context "#alert_enabled?" do
    test "returns a boolean" do
      budget = build(:budget)

      assert_equal budget.alert_enabled?, true
    end
  end

  context "#alert_recipients_user_ids" do
    test "returns an array of strings" do
      budget = build(:budget)

      assert_equal budget.alert_recipients_user_ids, ["1"]
    end
  end

  context "#current_amount" do
    test "returns a float" do
      budget = build(:budget)

      assert_equal budget.current_amount, 0.0
    end
  end

  context "#target_name" do
    test "returns a string" do
      customer = create(:customer, id: 12345)
      business = create(:business, slug: "avocado-corp", customer: customer)
      budget = build(:budget)

      assert_equal budget.target_name, "avocado-corp"
    end
  end

  context "#target" do
    test "returns a Business object" do
      customer = create(:customer, id: 12345)
      business = create(:business, slug: "avocado-corp", customer: customer)
      budget = build(:budget)

      assert_equal budget.target, business
    end
  end

  context "#visible_to?" do
    test "returns true for checking if business budget is visible to the business" do
      customer = create(:customer, id: 12345)
      business = create(:business, slug: "avocado-corp", customer: customer)
      budget = build(:budget)

      assert budget.visible_to? business
    end

    test "returns true for checking if business budget is visible to the assigned user" do
      business = create(:business, slug: "avocado-corp", id: 12345)
      user = create(:user)
      budget = build(:budget, recipientUserIds: [user.id.to_s])

      assert budget.visible_to? user
    end

    test "returns false for checking if business budget is visible to an unassigned user" do
      business = create(:business, slug: "avocado-corp", id: 12345)
      user = create(:user)
      budget = build(:budget)

      refute budget.visible_to? user
    end

    test "returns true when checking if a cost center budget is visible to the business" do
      customer = create(:customer, id: 12345)
      business = create(:business, slug: "avocado-corp", customer: customer)
      budget = build(:budget, customerId: customer.id, targetType: COSTCENTER_TARGET, targetId: "some-uuid")

      assert budget.visible_to? business
    end

    test "returns false when checking if a cost center budget is visible to a different business" do
      customer = create(:customer, id: 12345)
      business = create(:business, slug: "avocado-corp", customer: customer)
      budget = build(:budget, customerId: customer.id, targetType: COSTCENTER_TARGET, targetId: "some-uuid")
      some_other_business = create(:business, slug: "some-other-business")

      refute budget.visible_to? some_other_business
    end
  end

  context "#to_json" do
    test "returns json" do
      customer = create(:customer, id: 12345)
      business = create(:business, slug: "avocado-corp", customer: customer)
      budget = build(:budget)

      expected_json = {
        targetType: CUSTOMER_TARGET,
        targetAmount: 100.0,
        budgetLimitType: "AlertingOnly",
        currentAmount: 0.0,
        targetName: "avocado-corp",
        alertEnabled: true,
        alertRecipientUserIds: ["1"],
        targetId: "12345",
        pricingTargetId: "sku",
        uuid: "12345"
      }

      assert_equal budget.as_json, expected_json
    end
  end


  context "#to_edit_json" do
    test "returns json with user info" do
      customer = create(:customer, id: 12345)
      business = create(:business, slug: "avocado-corp", customer: customer)
      user1 = create(:user, login: "test1")
      user2 = create(:user, login: "test2")
      budget = build(
                :budget,
                willAlert: true,
                recipientUserIds: [user1.id.to_s, user2.id.to_s],
                pricingTargetId: "actions",
                pricingTargetType: "ProductPricing")

      expected_json = {
        targetType: CUSTOMER_TARGET,
        targetAmount: 100.0,
        budgetLimitType: "AlertingOnly",
        currentAmount: 0.0,
        targetName: "avocado-corp",
        targetId: "12345",
        uuid: "12345",
        alertEnabled: true,
        alertRecipientUserIds: [user1.global_relay_id, user2.global_relay_id],
        pricingTargetId: "actions",
        pricingTargetType: "ProductPricing"
      }
      actual_json = budget.to_edit_json

      assert_same_elements actual_json[:alertRecipientUserIds], expected_json[:alertRecipientUserIds]
      assert_equal actual_json.except(:alertRecipientUserIds), expected_json.except(:alertRecipientUserIds)
    end
  end

  context "#slug" do
    test "returns the uuid and target amount of a budget" do
      budget = build(:budget)

      assert_equal "12345-100.0", budget.slug
    end
  end

  context "#owner" do
    test "returns the correct owner of a cost center budget" do
      customer = create(:customer, id: 12345)
      business = create(:business, slug: "avocado-corp", customer: customer)
      budget = build(:budget, customerId: customer.id, targetType: COSTCENTER_TARGET, targetId: "some-uuid")

      assert_equal budget.owner, business
    end

    test "returns the correct owner of an enterprise budget" do
      customer = create(:customer, id: 12345)
      business = create(:business, slug: "avocado-corp", customer: customer)
      budget = build(:budget, customerId: customer.id)

      assert_equal budget.owner, business
    end

    test "returns the correct owner of an org budget" do
      org = create(:organization)
      budget = build(:budget, targetType: ORGANIZATION_TARGET, targetId: org.id)

      assert_equal budget.owner, org
    end

    test "returns the correct owner of a repo budget" do
      repo = create(:repository)
      budget = build(:budget, targetType: REPOSITORY_TARGET, targetId: repo.id)

      assert_equal budget.owner, repo.owner
    end
  end
end if GitHub.billing_enabled?
