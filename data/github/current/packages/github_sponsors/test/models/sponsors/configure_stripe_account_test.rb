# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsConfigureStripeAccountTest < GitHub::TestCase
  fixtures do
    @stripe_account = create(:stripe_connect_account)
    @listing = @stripe_account.sponsors_listing
    @sponsorable = @listing.sponsorable
    @staff = create(:staff_admin_user)
  end

  setup do
    skip unless GitHub.sponsors_enabled?
    @automatic_response = Stripe::Account.construct_from(
      id: @stripe_account.stripe_account_id,
      settings: {
        payouts: {
          schedule: {
            delay_days: 2,
            interval: "monthly",
            monthly_anchor: 22,
          },
        },
      },
    )
    @manual_response = Stripe::Account.construct_from(
      id: @stripe_account.stripe_account_id,
      settings: {
        payouts: {
          schedule: {
            delay_days: 2,
            interval: "manual",
          },
        },
      },
    )
  end

  context ".call" do
    test "allows freezing payouts" do
      Stripe::Account.stubs(:update).returns(@manual_response)

      account = Sponsors::ConfigureStripeAccount.call(account: @stripe_account, freeze_payouts: true)
      assert_equal @stripe_account.reload, account
      assert_equal "manual", @stripe_account.payout_interval
    end

    test "allows unfreezing payouts" do
      Stripe::Account.stubs(:update).returns(@automatic_response)

      account = Sponsors::ConfigureStripeAccount.call(account: @stripe_account, freeze_payouts: false)
      assert_equal @stripe_account.reload, account
      assert_equal "monthly", @stripe_account.payout_interval
    end

    test "instruments event for freezing payouts without actor" do
      Stripe::Account.stubs(:update).returns(@manual_response)
      events = subscribe "sponsors_listing.disable_payouts"

      Sponsors::ConfigureStripeAccount.call(account: @stripe_account, freeze_payouts: true)

      expected_payload = {
        user: @sponsorable.login,
        user_id: @sponsorable.id,
        sponsors_listing_id: @listing.id,
        actor: User.staff_user.login,
        actor_id: User.staff_user.id,
        short_description: @listing.short_description,
        sponsors_listing: @listing.slug,
        state: :draft,
        created_by: @listing.created_by.login,
        created_by_id: @listing.created_by_id,
      }

      refute_nil event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "instruments event for freezing payouts with actor" do
      Stripe::Account.stubs(:update).returns(@manual_response)
      events = subscribe "sponsors_listing.disable_payouts"

      Sponsors::ConfigureStripeAccount.call(
        account: @stripe_account,
        freeze_payouts: true,
        actor: @staff,
      )

      expected_payload = GitHub.guarded_audit_log_staff_actor_entry(@staff).merge(
        user: @sponsorable.login,
        user_id: @sponsorable.id,
        sponsors_listing_id: @listing.id,
        short_description: @listing.short_description,
        sponsors_listing: @listing.slug,
        state: :draft,
        created_by: @listing.created_by.login,
        created_by_id: @listing.created_by_id,
      )

      refute_nil event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "instruments event for unfreezing payouts without actor" do
      Stripe::Account.stubs(:update).returns(@automatic_response)
      events = subscribe "sponsors_listing.enable_payouts"

      Sponsors::ConfigureStripeAccount.call(account: @stripe_account, freeze_payouts: false)

      expected_payload = {
        user: @sponsorable.login,
        user_id: @sponsorable.id,
        sponsors_listing_id: @listing.id,
        actor: User.staff_user.login,
        actor_id: User.staff_user.id,
        short_description: @listing.short_description,
        sponsors_listing: @listing.slug,
        state: :draft,
        created_by: @listing.created_by.login,
        created_by_id: @listing.created_by_id,
      }

      refute_nil event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "instruments event for freezing payouts with reason" do
      Stripe::Account.stubs(:update).returns(@manual_response)
      events = subscribe "sponsors_listing.disable_payouts"

      Sponsors::ConfigureStripeAccount.call(
        account: @stripe_account,
        freeze_payouts: true,
        actor: @staff,
        reason: "fraud review",
      )

      expected_payload = GitHub.guarded_audit_log_staff_actor_entry(@staff).merge(
        user: @sponsorable.login,
        user_id: @sponsorable.id,
        sponsors_listing_id: @listing.id,
        reason: "fraud review",
        short_description: @listing.short_description,
        sponsors_listing: @listing.slug,
        state: :draft,
        created_by: @listing.created_by.login,
        created_by_id: @listing.created_by_id,
      )

      refute_nil event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "instruments event for unfreezing payouts with actor" do
      Stripe::Account.stubs(:update).returns(@automatic_response)
      events = subscribe "sponsors_listing.enable_payouts"

      Sponsors::ConfigureStripeAccount.call(
        account: @stripe_account,
        freeze_payouts: false,
        actor: @staff,
      )

      expected_payload = GitHub.guarded_audit_log_staff_actor_entry(@staff).merge(
        user: @sponsorable.login,
        user_id: @sponsorable.id,
        sponsors_listing_id: @listing.id,
        short_description: @listing.short_description,
        sponsors_listing: @listing.slug,
        state: :draft,
        created_by: @listing.created_by.login,
        created_by_id: @listing.created_by_id,
      )

      refute_nil event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end
  end
end
