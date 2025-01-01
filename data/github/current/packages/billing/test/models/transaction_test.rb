# typed: true
# frozen_string_literal: true

require "test_helper"

class TransactionTest < GitHub::TestCase
  fixtures do
    @small = GitHub::Plan.find("small").cost
    @user = create(:user, plan: "small")

    @sponsorable  = create(:user, :sponsorable)
    @default_tier = @sponsorable.sponsors_listing.default_tier
  end

  context "#humanized_action" do
    test "handles downgrades" do
      assert_equal "Changed", Transaction.new(action: "downgraded").humanized_action
    end

    test "handles upgrades" do
      assert_equal "Changed", Transaction.new(action: "upgraded").humanized_action
    end

    test "handles new sponsorships" do
      assert_equal "New sponsorship", Transaction.new(action: "sp_added").humanized_action
    end

    test "handles sponsorship cancellations" do
      assert_equal "Cancelled sponsorship", Transaction.new(action: "sp_cancelled").humanized_action
    end

    test "handles sponsorship tier changes" do
      assert_equal "Sponsorship tier changed", Transaction.new(action: "sp_changed").humanized_action
    end

    test "handles new subscriptions" do
      assert_equal "Subscription created", Transaction.new(action: "sub_created").humanized_action
    end

    test "handles cancelled subscriptions" do
      assert_equal "Subscription cancelled", Transaction.new(action: "sub_cancelled").humanized_action
    end

    test "handles subscription changes" do
      assert_equal "Subscription changed", Transaction.new(action: "sub_changed").humanized_action
    end

    test "handles unknown actions" do
      assert_equal "Taking a nice walk in the park",
        Transaction.new(action: "taking_a_nice_walk_in_the_park").humanized_action
    end
  end

  test "create signed-up transaction on user create" do
    assert_includes @user.transactions.map(&:action), "signed-up"
  end

  test "create deleted transaction on user destroy" do
    @user.destroy
    assert_includes @user.transactions.map(&:action), "deleted"
  end

  test "shows human-friendly plan names" do
    user = create :user, plan: "small"
    transaction = user.transactions.create(old_plan: "micro")
    assert_equal "Small", transaction.human_current_plan

    user = create :user, plan: nil
    transaction = user.transactions.create(old_plan: "micro")
    if GitHub.enterprise?
      assert_equal "Enterprise", transaction.human_current_plan
    else
      assert_equal "Free", transaction.human_current_plan
    end

    user = create :user, plan: "nonexistent-plan"
    transaction = user.transactions.create(old_plan: "micro")
    assert_nil transaction.human_current_plan
  end

  test "for_subscribables includes transactions to a Marketplace listing plan" do
    plans = create_list(:marketplace_listing_plan, 2, :published)
    transactions = plans.map { |plan| @user.transactions.create(current_subscribable: plan) }

    assert_same_elements transactions, Transaction.for_subscribables(plans)
  end

  test "for_subscribables includes transactions from a Marketplace listing plan" do
    plans = create_list(:marketplace_listing_plan, 2, :published)
    transactions = plans.map { |plan| @user.transactions.create(old_subscribable: plan) }

    assert_same_elements transactions, Transaction.for_subscribables(plans)
  end

  test "for_subscribables includes transactions to a Billing Product UUID" do
    plans = create_list(:billing_product_uuid, 1, :copilot)
    transactions = plans.map { |plan| @user.transactions.create(current_subscribable: plan) }

    assert_same_elements transactions, Transaction.for_subscribables(plans)
  end

  test "for_subscribables includes transactions from a Billing Product UUID" do
    plans = create_list(:billing_product_uuid, 1, :copilot)

    transactions = plans.map { |plan| @user.transactions.create(old_subscribable: plan) }

    assert_same_elements transactions, Transaction.for_subscribables(plans)
  end

  test "allows setting timestamp on creation" do
    user = create :user, plan: "small"
    timestamp = 3.days.ago
    transaction = user.transactions.create(old_plan: "micro", timestamp: timestamp)
    assert_equal timestamp.to_i, transaction.timestamp.to_i
  end

  test "sets current time as timestamp if not specified" do
    now = 3.days.ago

    Timecop.freeze(now) do
      user = create :user, plan: "small"
      timestamp = 3.days.ago
      transaction = user.transactions.create(old_plan: "micro")
      assert_equal now.to_i, transaction.timestamp.to_i
    end
  end

  context "paid" do
    test "does not include switched-to-yearly" do
      org = create(:organization, plan_duration: "year")
      create(:transaction, action: "switched-to-yearly", user: org)
      create(:transaction, action: "upgraded", user: org)
      assert_equal org.transactions.paid.pluck(:action), %w[signed-up upgraded]
    end
  end

  context "paid_and_switch" do
    test "includes switched-to-yearly" do
      org = create(:organization, plan_duration: "year")
      create(:transaction, action: "switched-to-yearly", user: org)
      create(:transaction, action: "upgraded", user: org)
      assert_equal org.transactions.paid_and_switch.pluck(:action), %w[signed-up switched-to-yearly upgraded]
    end
  end
end
