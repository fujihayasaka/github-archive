# typed: true
# frozen_string_literal: true

require "test_helper"

class UserInstrumentationDependencyTest < GitHub::TestCase
  fixtures do
    @user = create :user, plan: "free"
    @org  = create :organization, admin: @user, plan: "free"
  end

  setup do
    @events = subscribe "account.plan_change"
  end

  context "#track_plan_change" do
    test "upgrade a user (free -> small)" do
      small_user = create :user, plan: "small"
      old_plan   = GitHub::Plan.find "free"
      expected_payload = {
        old_plan: "free",
        plan: "small",
        old_plan_duration: "month",
        plan_duration: "month",
        old_seats: 0,
        seats: 0,
        old_data_packs: 0,
        asset_packs: 0,
        user: small_user.login,
        user_id: small_user.id,
        actor: small_user.login,
        actor_id: small_user.id,
        tos_sha: TosAcceptance.current_sha,
      }

      # stats
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      small_user.track_plan_change(small_user, old_plan)

      assert_equal 1, GitHub.dogstats.increments("user.plan", tags: ["action:upgrade"]).count
      # transaction
      transaction = small_user.transactions.last
      assert_equal "upgraded", transaction.action
      assert_equal "free", transaction.old_plan.name

      # instrumentation
      assert event = @events.pop
      assert_equal "account.plan_change", event.name
      assert_equal expected_payload, event.payload
    end

    test "obscures audit log details when actor is staff for plan_change" do
      small_user = create :user, plan: "small"
      staff = create :user, :staff
      old_plan   = GitHub::Plan.find "free"

      expected_payload = {
        old_plan: "free",
        plan: "small",
        old_plan_duration: "month",
        plan_duration: "month",
        old_seats: 0,
        seats: 0,
        old_data_packs: 0,
        asset_packs: 0,
        user: small_user.login,
        user_id: small_user.id,
        actor: User.staff_user.login,
        actor_id: User.staff_user.id,
        staff_actor: staff.login,
        staff_actor_id: staff.id,
        tos_sha: TosAcceptance.current_sha,
      }

      small_user.track_plan_change(staff, old_plan)

      # transaction
      transaction = small_user.transactions.last
      assert_equal "upgraded", transaction.action
      assert_equal "free", transaction.old_plan.name

      # instrumentation
      assert event = @events.pop
      assert_equal "account.plan_change", event.name
      assert_equal expected_payload, event.payload
    end unless GitHub.enterprise?

    test "upgrade with coupon (free -> micro)" do
      micro_user = create :user, plan: "micro"
      old_plan   = GitHub::Plan.find "free"
      coupon     = create :coupon, discount: 7
      expected_payload = {
        old_plan: "free",
        plan: "micro",
        old_plan_duration: "month",
        plan_duration: "month",
        old_seats: 0,
        seats: 0,
        old_data_packs: 0,
        asset_packs: 0,
        coupon: coupon.code,
        user: micro_user.login,
        user_id: micro_user.id,
        actor: @user.login,
        actor_id: @user.id,
        tos_sha: TosAcceptance.current_sha,
      }

      micro_user.track_plan_change(@user, old_plan,
        coupon: coupon)

      assert event = @events.pop
      assert_equal "account.plan_change", event.name
      assert_equal expected_payload, event.payload
    end

    test "downgrade a user with an apple iap subscription (pro -> free)" do
      free_user = create :user, plan: "free"
      old_plan = GitHub::Plan.find "pro"
      apple_iap = "Apple In-App Purchase"

      expected_payload = {
        old_plan: "pro",
        plan: "free",
        old_plan_duration: "month",
        plan_duration: "month",
        old_subscription_provider: apple_iap,
        old_seats: 0,
        seats: 0,
        old_data_packs: 0,
        asset_packs: 0,
        user: free_user.login,
        user_id: free_user.id,
        actor: @user.login,
        actor_id: @user.id,
        tos_sha: TosAcceptance.current_sha,
      }

      free_user.track_plan_change(@user, old_plan,
        old_subscription_provider: apple_iap)

      assert event = @events.pop
      assert_equal "account.plan_change", event.name
      assert_equal expected_payload, event.payload
    end

    test "records tos acceptance sha" do
      micro_user = create :user, plan: "micro"
      old_plan   = GitHub::Plan.find "free"
      coupon     = create :coupon, discount: 7
      expected_payload = {
        old_plan: "free",
        plan: "micro",
        old_plan_duration: "month",
        plan_duration: "month",
        old_seats: 0,
        seats: 0,
        old_data_packs: 0,
        asset_packs: 0,
        coupon: coupon.code,
        user: micro_user.login,
        user_id: micro_user.id,
        actor: @user.login,
        actor_id: @user.id,
        tos_sha: TosAcceptance.current_sha,
      }

      micro_user.track_plan_change(@user, old_plan,
        coupon: coupon)

      assert event = @events.pop
      assert_equal "account.plan_change", event.name
      assert_equal expected_payload, event.payload
    end

    test "upgrade with repo creation (free -> micro)" do
      micro_user = create :user, plan: "micro"
      old_plan   = GitHub::Plan.find "free"
      repo       = create(:private_repository, owner: micro_user)

      micro_user.track_plan_change(@user, old_plan,
        repository: repo)

      event = @events.pop
      assert_equal "account.plan_change", event.name
      assert_equal repo.full_name, event.payload[:repository]
    end

    test "downgrade an org (bronze -> free)" do
      old_plan = GitHub::Plan.find "bronze"
      billing_transaction = create(:billing_transaction,
        user_id: @org,
        amount_in_cents: 700,
        transaction_id: "abc123",
        transaction_type: "refund",
      )
      expected_payload = {
        old_plan: "bronze",
        plan: "free",
        old_plan_duration: "month",
        plan_duration: "month",
        old_seats: 0,
        seats: 0,
        old_data_packs: 0,
        asset_packs: 0,
        tos_sha: TosAcceptance.current_sha,
        org: @org.login,
        org_id: @org.id,
        actor: @user.login,
        actor_id: @user.id,
      }

      # stats
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      @org.track_plan_change(@user, old_plan,
        billing_transaction: billing_transaction)

      assert_equal 1, GitHub.dogstats.increments("user.plan", tags: ["action:downgrade"]).count
      # transaction
      transaction = @org.transactions.last
      assert_equal billing_transaction, transaction.billing_transaction
      assert_equal "downgraded", transaction.action

      # instrumentation
      assert event = @events.pop
      assert_equal "account.plan_change", event.name
      assert_equal expected_payload, event.payload
    end

    test "not an actual plan change" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      @user.track_plan_change(@user, @user.plan)

      assert_equal 0, GitHub.dogstats.increments("user.plan.downgrade").count
      assert_equal 1, @org.transactions.size
      refute @events.pop
    end
  end

  context "#track_data_pack_changes" do
    test "add asset packs" do
      micro_user = create :user, plan: "micro"
      old_plan   = GitHub::Plan.find "free"
      expected_payload = {
        old_plan: "micro",
        plan: "micro",
        old_plan_duration: "month",
        plan_duration: "month",
        old_seats: 0,
        seats: 0,
        old_data_packs: 0,
        asset_packs: 1,
        user: micro_user.login,
        user_id: micro_user.id,
        actor: @user.login,
        actor_id: @user.id,
        tos_sha: TosAcceptance.current_sha,
      }

      Asset::Status.create! owner: micro_user, asset_packs: 1
      micro_user.track_data_pack_change(@user, old_data_packs: 0)

      assert event = @events.pop
      assert_equal "account.plan_change", event.name
      assert_equal expected_payload, event.payload
      assert transaction = micro_user.transactions.last
      assert_equal 1, transaction.asset_packs_total
      assert_equal 1, transaction.asset_packs_delta
    end
  end

  context "track_subscription_item_change_for_user_duration_change" do
    test "sends webhooks" do
      current_time = Time.now
      Timecop.freeze(current_time) do
        item = create :billing_subscription_item
        user = item.account

        Hook::Event::MarketplacePurchaseEvent.expects(:queue).with(equals(
          subscription_item_id: item.id,
          sender_id: user.id,
          previous_plan_duration: "month",
          action: "changed",
          triggered_at: current_time
        ))

        user.track_subscription_item_change_for_user_duration_change(user, previous_plan_duration: "month")
      end
    end

    test "does not pick up product UUID subscribables" do
      # ProductUUID subscribables have their own billing cycle and
      # are not dependent on the user's plan duration.
      item = create :billing_subscription_item, :with_product_uuid
      user = item.account
      sponsorship = create :sponsors_subscription_item, account: user

      GitHub.expects(:instrument).with(
        "sponsorship.changed",
        subscription_item_id: sponsorship.id,
        sender_id: user.id,
        previous_plan_duration: "month"
      )
      user.track_subscription_item_change_for_user_duration_change(user, previous_plan_duration: "month")
    end
  end

  test "#instrument_async_delete? returns true" do
    assert_predicate create(:user), :instrument_async_delete?
  end
end
