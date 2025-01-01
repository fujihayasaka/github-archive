# typed: true
# frozen_string_literal: true

require "test_helper"

class Sponsorship::PendingChangeTest < GitHub::TestCase
  fixtures do
    @sponsorship = create(:sponsorship)
    @sub_item = @sponsorship.subscription_item
    @sponsor = @sponsorship.sponsor
    @sponsorable = @sponsorship.sponsorable
    @sponsors_listing = @sponsorable.sponsors_listing
    @lower_price_tier = @sponsorship.tier
    @higher_price_tier = create(:sponsors_tier, :published, sponsors_listing: @sponsors_listing)
    @pending_sub_item_change = create(:billing_pending_subscription_item_change,
      quantity: 1,
      subscribable: @lower_price_tier,
      account: @sponsor,
    )
  end

  context "#type" do
    test "returns Type::Cancellation when pending change sets quantity to 0" do
      @pending_sub_item_change.update!(quantity: 0)
      pending_cancellation = @pending_sub_item_change

      pending_change = Sponsorship::PendingChange.new(
        current_subscription_item: @sub_item,
        pending_subscription_item_change: pending_cancellation,
      )

      assert_equal Sponsorship::PendingChange::Type::Cancellation, pending_change.type
    end

    test "returns Type::Activation when pending change sets inactive sub item quantity to 1" do
      @sub_item.update!(quantity: 0)
      inactive_sub_item = @sub_item
      pending_activation = @pending_sub_item_change

      pending_change = Sponsorship::PendingChange.new(
        current_subscription_item: inactive_sub_item,
        pending_subscription_item_change: pending_activation,
      )

      assert_equal Sponsorship::PendingChange::Type::Activation, pending_change.type
    end

    test "returns Type::Activation when no current sub item and pending change with a quantity of 1" do
      pending_activation = @pending_sub_item_change

      pending_change = Sponsorship::PendingChange.new(
        current_subscription_item: nil,
        pending_subscription_item_change: pending_activation,
      )

      assert_equal Sponsorship::PendingChange::Type::Activation, pending_change.type
    end

    test "returns Type::Downgrade when pending change is for lower price tier" do
      @sub_item.update!(subscribable: @higher_price_tier)
      higher_price_sub_item = @sub_item
      lower_price_change = @pending_sub_item_change

      pending_change = Sponsorship::PendingChange.new(
        current_subscription_item: higher_price_sub_item,
        pending_subscription_item_change: lower_price_change,
      )

      assert_equal Sponsorship::PendingChange::Type::Downgrade, pending_change.type
    end

    test "returns Type::Upgrade when pending change is for higher price tier" do
      lower_price_sub_item = @sub_item
      @pending_sub_item_change.update!(subscribable: @higher_price_tier)
      higher_price_change = @pending_sub_item_change

      pending_change = Sponsorship::PendingChange.new(
        current_subscription_item: lower_price_sub_item,
        pending_subscription_item_change: higher_price_change,
      )

      assert_equal Sponsorship::PendingChange::Type::Upgrade, pending_change.type
    end

    test "returns Type::NOP when no change to tier or quantity" do
      pending_change = Sponsorship::PendingChange.new(
        current_subscription_item: @sub_item,
        pending_subscription_item_change: @pending_sub_item_change,
      )

      assert_equal Sponsorship::PendingChange::Type::NOP, pending_change.type
    end
  end

  context "#activation?" do
    test "returns true for pending activation" do
      pending_change = create(:sponsorship, :pending_activation).pending_change
      assert_predicate pending_change, :activation?
    end

    test "returns false for other pending change" do
      pending_change = create(:sponsorship, :pending_cancellation).pending_change
      refute_predicate pending_change, :activation?
    end
  end

  context "#name" do
    test "returns name for pending change" do
      sponsorship = create(:sponsorship, :pending_activation)
      pending_change = sponsorship.pending_change
      assert_equal "pending activation", pending_change.name
    end
  end

  context "#to_s" do
    test "returns name for pending change" do
      sponsorship = create(:sponsorship, :pending_cancellation)
      pending_change = sponsorship.pending_change
      assert_equal "pending cancellation", pending_change.to_s
    end
  end

  context "#description" do
    test "returns pending change description" do
      sponsorship = create(:sponsorship, :pending_downgrade)
      pending_change = sponsorship.pending_change
      expected_change = pending_change.name
      expected_active_on = pending_change.active_on.strftime("%b %d, %Y")
      expected_new_tier = pending_change.new_tier
      assert_equal(
        "#{expected_change} to #{expected_new_tier} effective #{expected_active_on}",
        pending_change.description
      )
    end
  end

  context "#active_on" do
    test "returns the active on date from the pending subscription item change" do
      pending_change = Sponsorship::PendingChange.new(
        current_subscription_item: @sub_item,
        pending_subscription_item_change: @pending_sub_item_change,
      )

      assert_equal @pending_sub_item_change.active_on, pending_change.active_on
    end
  end

  context "#new_tier" do
    test "returns the subscribable from the pending subscription item change" do
      pending_change = Sponsorship::PendingChange.new(
        current_subscription_item: nil,
        pending_subscription_item_change: @pending_sub_item_change,
      )

      assert_equal @pending_sub_item_change.subscribable, pending_change.new_tier
    end

    test "returns nil for a cancellation" do
      @pending_sub_item_change.update!(quantity: 0)
      pending_cancellation = @pending_sub_item_change

      pending_change = Sponsorship::PendingChange.new(
        current_subscription_item: @sub_item,
        pending_subscription_item_change: pending_cancellation,
      )

      assert_nil pending_change.new_tier
    end
  end
end
