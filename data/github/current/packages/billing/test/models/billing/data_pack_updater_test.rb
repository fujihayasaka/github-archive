# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::DataPackUpdaterTest < GitHub::TestCase
  include GitHub::BillingTest

  fixtures do
    @user = create(:user)
    @org = create(:organization)
  end

  def user_with_plan_subscription
    user = create :credit_card_user, :with_valid_contact_for_billing, plan: "pro"
    user.plan_subscription = create :billing_plan_subscription

    Asset::Status.create owner: user, asset_packs: 5
    user
  end

  context "#update" do
    test "fails when target is spammy and buying packs" do
      @user.update spammy: true
      updater = Billing::DataPackUpdater.new(@user, total_packs: 2, actor: @user)

      refute updater.update
      assert_match /Your account is flagged and unable to make purchases/, updater.error
    end

    test "fails when target is disabled and buying packs" do
      user = create(:billing_locked_user)
      updater = Billing::DataPackUpdater.new(user, total_packs: 2, actor: user)

      refute updater.update
      assert_match /Your account is currently locked from purchases/, updater.error
    end

    test "fails when target is trade restricted and buying packs" do
      user = create(:user, :partially_trade_restricted)

      updater = Billing::DataPackUpdater.new(user, total_packs: 2, actor: user)

      refute updater.update
      assert_match /Due to U.S. trade controls law restrictions, your GitHub account has been restricted/, updater.error
    end

    test "fails when number of packs to be added is greater than per request limit" do
      updater = Billing::DataPackUpdater.new(@user, total_packs: 110, actor: @user)

      refute updater.update
      assert_equal "Oops, please enter a quantity of data packs less than #{Billing::DataPackUpdater::MAXIMUM_PACKS_PER_REQUEST}", updater.error
    end

    test "fails when target is purchasing less than minimum packs" do
      updater = Billing::DataPackUpdater.new(@user, total_packs: -1, actor: @user)

      refute updater.update
      assert_equal "Oops, please enter a quantity of data packs between 0 and 10000.", updater.error
    end

    test "fails when target is purchasing more than maximum packs" do
      Asset::Status.create owner: @user, asset_packs: 9990
      updater = Billing::DataPackUpdater.new(@user, total_packs: 10001, actor: @user)

      refute updater.update
      assert_equal "Oops, please enter a quantity of data packs between 0 and 10000.", updater.error
    end

    test "fails when target is in a sales managed business" do
      business = create(:business, can_self_serve: false)
      business.add_organization(@org)
      @org.reload
      updater = Billing::DataPackUpdater.new(@org, total_packs: 2, actor: @user)

      refute updater.update
      assert_equal "Please contact your GitHub Enterprise account representative to add more data packs to your plan.", updater.error
    end

    test "fails when target has no valid payment method" do
      updater = Billing::DataPackUpdater.new(@org, total_packs: 2, actor: @user)

      refute updater.update
      assert_equal "Please add a payment method to your account.", updater.error
    end

    test "updates datapacks when target and packs are valid" do
      user = user_with_plan_subscription
      updater = Billing::DataPackUpdater.new(user, total_packs: 5, actor: user)

      assert updater.update
      assert_equal 5, user.reload.data_packs
    end
  end
end
