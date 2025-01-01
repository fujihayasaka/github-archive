# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Stripe::TransferTestCase < GitHub::BillingTestCase
  fixtures do
    @user = create(:billing_transaction, platform_transaction_id: @platform_transaction_id).user
  end

  setup do
    @platform_transaction_id = "2c92c0fb6ff08ce9016ff2af7b205d7d"
    @destination = "acct_1G61WUJWUR5CcHHA"
    @destination_currency = "usd"
    @base_transfers = VCR.use_cassette("stripe/retrieve_destination_records") do
      Billing::Stripe::Transfer.list(destination: @destination, destination_currency: @destination_currency)
    end
  end

  context "#amount_reversed" do
    test "returns the payment amount and match amount that have been reversed" do
      stripe_transfer = VCR.use_cassette("stripe/retrieve_fully_reversed_transfer") do
        Stripe::Transfer.retrieve("tr_1GfCrnEQsq43iHhX39uz2uCk")
      end
      transfer = Billing::Stripe::Transfer.from_transfer(stripe_transfer)

      amount_reversed = transfer.amount_reversed

      assert_equal Billing::Money.new(10_00), amount_reversed
      assert_equal amount_reversed, transfer.payment_amount_reversed + transfer.match_amount_reversed,
        "expected the amount reversed to include payment reversed and match reversed"
    end

    test "returns $0 when none of the amount was reversed" do
      stripe_transfer = VCR.use_cassette("stripe/retrieve_transfer_without_reversal") do
        Stripe::Transfer.retrieve("tr_1G77IOEQsq43iHhXZmQb0ecK")
      end
      transfer = Billing::Stripe::Transfer.from_transfer(stripe_transfer)

      assert_equal Billing::Money.zero, transfer.amount_reversed
    end
  end

  context "#fully_reversed?" do
    test "returns true for a full reversal of the total amount, payment and match" do
      stripe_transfer = VCR.use_cassette("stripe/retrieve_fully_reversed_transfer") do
        Stripe::Transfer.retrieve("tr_1GfCrnEQsq43iHhX39uz2uCk")
      end
      transfer = Billing::Stripe::Transfer.from_transfer(stripe_transfer)

      assert_predicate transfer, :fully_reversed?
    end

    test "returns false for a transfer without any reversals" do
      stripe_transfer = VCR.use_cassette("stripe/retrieve_transfer_without_reversal") do
        Stripe::Transfer.retrieve("tr_1G77IOEQsq43iHhXZmQb0ecK")
      end
      transfer = Billing::Stripe::Transfer.from_transfer(stripe_transfer)

      refute_predicate transfer, :fully_reversed?
    end

    test "returns false for a transfer with some reversals that sum to less than the total amount" do
      stripe_transfer = VCR.use_cassette("stripe/retrieve_partially_reversed_transfer") do
        Stripe::Transfer.retrieve("tr_1G60MTEQsq43iHhXoIM7Ppjx")
      end
      transfer = Billing::Stripe::Transfer.from_transfer(stripe_transfer)

      refute_predicate transfer, :fully_reversed?
    end
  end

  context "#partially_reversed?" do
    test "returns false for a full reversal of the total amount, payment and match" do
      stripe_transfer = VCR.use_cassette("stripe/retrieve_fully_reversed_transfer") do
        Stripe::Transfer.retrieve("tr_1GfCrnEQsq43iHhX39uz2uCk")
      end
      transfer = Billing::Stripe::Transfer.from_transfer(stripe_transfer)

      refute_predicate transfer, :partially_reversed?
    end

    test "returns false for a transfer without any reversals" do
      stripe_transfer = VCR.use_cassette("stripe/retrieve_transfer_without_reversal") do
        Stripe::Transfer.retrieve("tr_1G77IOEQsq43iHhXZmQb0ecK")
      end
      transfer = Billing::Stripe::Transfer.from_transfer(stripe_transfer)

      refute_predicate transfer, :partially_reversed?
    end

    test "returns true for a transfer with some reversals that sum to less than the total amount" do
      stripe_transfer = VCR.use_cassette("stripe/retrieve_partially_reversed_transfer") do
        Stripe::Transfer.retrieve("tr_1G60MTEQsq43iHhXoIM7Ppjx")
      end
      transfer = Billing::Stripe::Transfer.from_transfer(stripe_transfer)

      assert_predicate transfer, :partially_reversed?
    end
  end

  context ".from_transfer" do
    test "hydrates our version of a transfer with data from Stripe" do
      transfer_id = "tr_1GcyIQEQsq43iHhXUusuRy3B"
      transfer_group = "2c92c0fb71baf4d40171c2059e600d06"
      tier = create(:sponsors_tier, :approved_sponsors_listing, monthly_price_in_cents: 5_00)
      sponsorship = create(:sponsorship, tier: tier)
      billing_transaction = create(:billing_transaction, :zuora, platform_transaction_id: transfer_group,
        user: sponsorship.sponsor, amount_in_cents: tier.monthly_price_in_cents)
      line_item1 = create(:billing_transaction_line_item, :sponsors, billing_transaction: billing_transaction,
        subscribable: tier)
      line_item2 = create(:billing_transaction_line_item, :sponsors, billing_transaction: billing_transaction,
        subscribable: tier)

      transfer = VCR.use_cassette("stripe/lookup_transfer_with_metadata") do
        ::Stripe::Transfer.retrieve(transfer_id)
      end

      stripe_transfer = Billing::Stripe::Transfer.from_transfer(transfer, billing_transaction: billing_transaction)

      assert_instance_of Billing::Stripe::Transfer, stripe_transfer
      assert_equal transfer_id, stripe_transfer.transfer_id
      assert_equal transfer_id, stripe_transfer.id
      assert_equal transfer_group, stripe_transfer.transfer_group
      assert_equal Billing::Money.new(5_00, "usd"), stripe_transfer.amount
      assert_equal Billing::Money.new(0, "usd"), stripe_transfer.match_amount
      assert_equal Billing::Money.new(0, "usd"), stripe_transfer.match_amount_reversed
      assert_equal "acct_1Ep35IFxJZYbadPl", stripe_transfer.destination
      assert_equal "usd", stripe_transfer.destination_currency
      assert_equal Billing::Money.new(5_00, "usd"), stripe_transfer.destination_amount
      assert_equal Time.at(1588099002).utc.to_datetime, stripe_transfer.transferred_at
      refute_nil stripe_transfer.reversals
      refute_nil stripe_transfer.metadata
      assert_equal "500", stripe_transfer.metadata["payment_amount"]
      assert_equal "0", stripe_transfer.metadata["match_amount"]
      assert_equal "ch_1Gcy3YEQsq43iHhXaA0elAxk", stripe_transfer.metadata["stripe_charge_id"]
      assert_equal billing_transaction.transaction_id, stripe_transfer.original_transaction_id
      assert_equal billing_transaction.user, stripe_transfer.sponsor
      assert_equal billing_transaction.user_id, stripe_transfer.sponsor_id
      assert_equal sponsorship.sponsor_login, stripe_transfer.sponsor_login
      assert_same_elements [line_item1, line_item2], stripe_transfer.sponsorship_line_items
    end

    test "supports transfers from enterprise account member orgs" do
      transfer_id = "tr_1GcyIQEQsq43iHhXUusuRy3B"
      transfer_group = "2c92c0fb71baf4d40171c2059e600d06"
      tier = create(:sponsors_tier, :approved_sponsors_listing, monthly_price_in_cents: 5_00)
      sub_item = create(:sponsors_subscription_item, :self_serve_business, subscribable: tier)
      sponsorship = create(:sponsorship,
        sponsor: sub_item.organization,
        tier: tier,
        subscription_item: sub_item
      )
      transaction = create(:billing_transaction, :business_owned,
        platform_transaction_id: transfer_group,
        customer: sub_item.customer
      )
      line_item = create(:billing_transaction_line_item,
        billing_transaction: transaction,
        subscribable: tier,
        amount_in_cents: tier.monthly_price_in_cents,
        extras: { managing_entity_id: sub_item.organization_id }
      )

      assert_equal sponsorship, line_item.sponsorship

      transfer = VCR.use_cassette("stripe/lookup_transfer_with_metadata") do
        ::Stripe::Transfer.retrieve(transfer_id)
      end

      stripe_transfer = Billing::Stripe::Transfer.from_transfer(transfer, billing_transaction: transaction)
      assert_equal sponsorship.sponsor_id, stripe_transfer.sponsor_id
      assert_equal sponsorship.sponsor_login, stripe_transfer.sponsor_login
    end
  end

  context "#payment_amount" do
    test "returns how much was paid, excluding the GitHub match portion" do
      stripe_transfer = VCR.use_cassette("stripe/retrieve_fully_reversed_transfer") do
        Stripe::Transfer.retrieve("tr_1GfCrnEQsq43iHhX39uz2uCk")
      end
      transfer = Billing::Stripe::Transfer.from_transfer(stripe_transfer)

      assert_equal Billing::Money.new(5_00), transfer.payment_amount
    end
  end

  context "#payment_amount_reversed" do
    test "returns how much of the payment was reversed, excluding how much of the GitHub match was reversed" do
      stripe_transfer = VCR.use_cassette("stripe/retrieve_fully_reversed_transfer") do
        Stripe::Transfer.retrieve("tr_1GfCrnEQsq43iHhX39uz2uCk")
      end
      transfer = Billing::Stripe::Transfer.from_transfer(stripe_transfer)

      assert_equal Billing::Money.new(5_00), transfer.payment_amount_reversed
    end

    test "returns $0 when payment was never reversed" do
      stripe_transfer = VCR.use_cassette("stripe/retrieve_transfer_without_reversal") do
        Stripe::Transfer.retrieve("tr_1G77IOEQsq43iHhXZmQb0ecK")
      end
      transfer = Billing::Stripe::Transfer.from_transfer(stripe_transfer)

      assert_equal Billing::Money.zero, transfer.payment_amount_reversed
    end
  end

  context "#sponsor" do
    test "returns provided sponsor without doing a database lookup" do
      User.expects(:find_by_login).never
      transfer = Billing::Stripe::Transfer.new(sponsor: @user)
      @user.delete
      assert_equal @user, transfer.sponsor
    end

    test "returns nil for nil sponsor" do
      transfer = Billing::Stripe::Transfer.new(sponsor: nil)
      assert_nil transfer.sponsor
    end
  end

  context "#reversals" do
    test "returns a list of reversals associated with the transfer" do
      stripe_transfer = VCR.use_cassette("stripe/retrieve_fully_reversed_transfer") do
        Stripe::Transfer.retrieve("tr_1GfCrnEQsq43iHhX39uz2uCk")
      end
      transfer = Billing::Stripe::Transfer.from_transfer(stripe_transfer)

      reversals = transfer.reversals

      refute_empty reversals
      assert reversals.all? { |reversal| reversal.is_a?(Stripe::Reversal) }
    end

    test "returns an empty list when transfer has not been reversed" do
      stripe_transfer = VCR.use_cassette("stripe/retrieve_transfer_without_reversal") do
        Stripe::Transfer.retrieve("tr_1G77IOEQsq43iHhXZmQb0ecK")
      end
      transfer = Billing::Stripe::Transfer.from_transfer(stripe_transfer)

      assert_empty transfer.reversals
    end
  end

  context "#sponsor_has_customized_user_profile?" do
    test "returns true when sponsor has a profile name" do
      create(:profile, user: @user, name: "foo")
      transfer = Billing::Stripe::Transfer.new(sponsor: @user)
      assert_predicate transfer, :sponsor_has_customized_user_profile?
    end

    test "returns true when sponsor has a profile bio" do
      create(:profile, user: @user, bio: "foo")
      transfer = Billing::Stripe::Transfer.new(sponsor: @user)
      assert_predicate transfer, :sponsor_has_customized_user_profile?
    end

    test "returns true when sponsor has a profile website URL" do
      create(:profile, user: @user, blog: "foo")
      transfer = Billing::Stripe::Transfer.new(sponsor: @user)
      assert_predicate transfer, :sponsor_has_customized_user_profile?
    end

    test "returns true when sponsor has a profile company" do
      create(:profile, user: @user, company: "foo")
      transfer = Billing::Stripe::Transfer.new(sponsor: @user)
      assert_predicate transfer, :sponsor_has_customized_user_profile?
    end

    test "returns true when sponsor has a profile Twitter username" do
      create(:profile, user: @user, twitter_username: "foo")
      transfer = Billing::Stripe::Transfer.new(sponsor: @user)
      assert_predicate transfer, :sponsor_has_customized_user_profile?
    end

    test "returns false when sponsor has no profile" do
      transfer = Billing::Stripe::Transfer.new(sponsor: @user)
      refute_predicate transfer, :sponsor_has_customized_user_profile?
    end

    test "returns false when sponsor has a profile but lacks customization in fields we care about" do
      create(:profile, user: @user, email: "someemail@example.com", name: " ", bio: "", twitter_username: nil,
        blog: nil, company: nil)
      transfer = Billing::Stripe::Transfer.new(sponsor: @user)
      refute_predicate transfer, :sponsor_has_customized_user_profile?
    end

    # See: https://github.com/github/sponsors/issues/3321
    # and https://github.com/github/sponsors/issues/4340
    test "returns false when sponsor is a deleted user" do
      transaction = create(:billing_transaction)
      transaction.live_user.destroy!
      transaction = Billing::BillingTransaction.find(transaction.id)

      transfer = Billing::Stripe::Transfer.new(sponsor: transaction.user)

      refute_predicate transfer, :sponsor_has_customized_user_profile?
    end
  end

  context "#sponsor_has_young_github_account?" do
    test "returns true for transfer whose sponsor signed up within the last 60 days" do
      user = travel_to(1.day.ago) { create(:user, :verified) }
      transfer = Billing::Stripe::Transfer.new(sponsor: user)
      assert_predicate transfer, :sponsor_has_young_github_account?
    end

    test "returns false for transfer whose sponsor signed up more than 60 days ago" do
      user = travel_to(61.days.ago) { create(:user, :verified) }
      transfer = Billing::Stripe::Transfer.new(sponsor: user)
      refute_predicate transfer, :sponsor_has_young_github_account?
    end
  end

  context "#sponsor_has_time_zone_matching_ip_address?" do
    test "returns true when sponsor has a time zone matching their IP address" do
      @user.update!(time_zone_name: "Pacific Time (US & Canada)", last_ip: "1.2.3.4")
      GitHub::Location.stubs(:look_up).returns(country_code: "US")
      transfer = Billing::Stripe::Transfer.new(sponsor: @user)
      assert_predicate transfer, :sponsor_has_time_zone_matching_ip_address?
    end

    test "returns true when sponsor has no IP address or time zone" do
      assert_nil @user.last_ip
      assert_nil @user.time_zone_name
      transfer = Billing::Stripe::Transfer.new(sponsor: @user)
      assert_predicate transfer, :sponsor_has_time_zone_matching_ip_address?
    end

    test "returns false when sponsor has no IP address but does have a time zone" do
      @user.update!(time_zone_name: "Pacific Time (US & Canada)")
      assert_nil @user.last_ip
      transfer = Billing::Stripe::Transfer.new(sponsor: @user)
      refute_predicate transfer, :sponsor_has_time_zone_matching_ip_address?
    end

    test "returns false when we can't determine the country for a sponsor's IP address" do
      @user.update!(time_zone_name: "Pacific Time (US & Canada)", last_ip: "1.2.3.4")
      GitHub::Location.stubs(:look_up).returns({})
      transfer = Billing::Stripe::Transfer.new(sponsor: @user)
      refute_predicate transfer, :sponsor_has_time_zone_matching_ip_address?
    end

    test "returns false when sponsor has a time zone that does not match their IP address" do
      @user.update!(time_zone_name: "Pacific Time (US & Canada)", last_ip: "1.2.3.4")
      GitHub::Location.stubs(:look_up).returns(country_code: "ES")
      transfer = Billing::Stripe::Transfer.new(sponsor: @user)
      refute_predicate transfer, :sponsor_has_time_zone_matching_ip_address?
    end

    # See https://github.com/github/sponsors/issues/3747
    test "returns true when sponsor has an Asia/Calcutta time zone and an India IP address" do
      @user.update!(time_zone_name: "Asia/Calcutta", last_ip: "1.2.3.4")
      GitHub::Location.stubs(:look_up).returns(country_code: "IN")
      transfer = Billing::Stripe::Transfer.new(sponsor: @user)
      assert_predicate transfer, :sponsor_has_time_zone_matching_ip_address?
    end

    # See: https://github.com/github/sponsors/issues/4512
    test "returns true when sponsor derived from a deleted user's billing transaction" do
      transaction = create(:billing_transaction)
      transaction.live_user.destroy!
      transaction_with_deleted_user = Billing::BillingTransaction.find(transaction.id)

      transfer_id = "tr_1GcyIQEQsq43iHhXUusuRy3B"
      transfer = VCR.use_cassette("stripe/lookup_transfer_with_metadata") do
        ::Stripe::Transfer.retrieve(transfer_id)
      end

      transfer = Billing::Stripe::Transfer.from_transfer(transfer,
        billing_transaction: transaction_with_deleted_user
      )

      assert_nil transfer.sponsor_time_zone_name
      assert_equal "none", transfer.sponsor_ip_address_country_name
      assert_predicate transfer, :sponsor_has_time_zone_matching_ip_address?
    end
  end

  context "#sponsor_time_zone_name" do
    test "returns sponsor's time zone name" do
      @user.update!(time_zone_name: "Pacific Time (US & Canada)")
      transfer = Billing::Stripe::Transfer.new(sponsor: @user)
      assert_equal "Pacific Time (US & Canada)", transfer.sponsor_time_zone_name
    end

    test "returns nil when no sponsor is specified" do
      transfer = Billing::Stripe::Transfer.new(sponsor: nil)
      assert_nil transfer.sponsor_time_zone_name
    end
  end

  context "#user_sponsor?" do
    test "returns true when sponsor is a user" do
      transfer = Billing::Stripe::Transfer.new(sponsor: @user)
      assert_predicate transfer, :user_sponsor?
    end

    test "returns false when sponsor is an organization" do
      org = create(:organization)
      transfer = Billing::Stripe::Transfer.new(sponsor: org)
      refute_predicate transfer, :user_sponsor?
    end
  end

  context "#sponsor_ip_address_country_name" do
    test "returns none when no sponsor is specified" do
      transfer = Billing::Stripe::Transfer.new(sponsor: nil)
      assert_equal "none", transfer.sponsor_ip_address_country_name
    end

    test "returns none when sponsor does not have an IP address" do
      assert_nil @user.last_ip
      transfer = Billing::Stripe::Transfer.new(sponsor: @user)
      assert_equal "none", transfer.sponsor_ip_address_country_name
    end

    test "returns name of the country associated with the sponsor's IP address" do
      @user.update!(last_ip: "1.2.3.4")
      GitHub::Location.stubs(:look_up).returns(country_name: "Spain")
      transfer = Billing::Stripe::Transfer.new(sponsor: @user)
      assert_equal "Spain", transfer.sponsor_ip_address_country_name
    end
  end

  context "#sponsor_login" do
    test "returns login from the given sponsor record" do
      transfer = Billing::Stripe::Transfer.new(sponsor: @user)
      assert_equal @user.login, transfer.sponsor_login
    end

    test "returns nil if no sponsor record" do
      transfer = Billing::Stripe::Transfer.new(sponsor: nil)
      assert_nil transfer.sponsor_login
    end
  end

  context "#dead_sponsor?" do
    test "returns true when sponsor is a deleted user" do
      transaction = create(:billing_transaction, user: @user)
      @user.delete
      dead_user = transaction.dead_user
      transfer = Billing::Stripe::Transfer.new(sponsor: dead_user)

      assert_predicate transfer, :dead_sponsor?
    end

    test "returns true when sponsor is a deleted organization" do
      org = create(:organization, plan: "silver")
      transaction = create(:billing_transaction, user: org, user_type: "organization")
      dead_org = transaction.dead_user
      transfer = Billing::Stripe::Transfer.new(sponsor: dead_org)

      assert_predicate transfer, :dead_sponsor?
    end

    test "returns false when sponsor is a live user" do
      transfer = Billing::Stripe::Transfer.new(sponsor: @user)

      refute_predicate transfer, :dead_sponsor?
    end

    test "returns false when sponsor is a live organization" do
      org = create(:organization)
      transfer = Billing::Stripe::Transfer.new(sponsor: org)

      refute_predicate transfer, :dead_sponsor?
    end
  end

  context ".list" do
    test "retrieves the records for the destination Stripe Connect account" do
      first_transfer  = @base_transfers.detect { |t| t.transfer_id == "tr_1G6Lp0EQsq43iHhXRsSjC8T9" }
      second_transfer = @base_transfers.detect { |t| t.transfer_id == "tr_1G62pvEQsq43iHhXeRGAcbsH" }

      assert_equal 11, @base_transfers.count

      assert_equal ::Billing::Money.new(500), first_transfer.match_amount
      assert_equal ::Billing::Money.new(500), first_transfer.match_amount_reversed
      assert_equal ::Billing::Money.new(1000), first_transfer.destination_amount
      assert_equal 1580324610, first_transfer.transferred_at.to_i
      assert first_transfer.match_fully_reversed?
      refute first_transfer.possibility_of_reversal_mismatch?

      assert_equal ::Billing::Money.new(500), second_transfer.match_amount
      assert_equal ::Billing::Money.new(500), second_transfer.match_amount_reversed
      assert_nil second_transfer.destination_amount
      assert_equal 1580251631, second_transfer.transferred_at.to_i
      assert second_transfer.match_fully_reversed?
      refute second_transfer.possibility_of_reversal_mismatch?
    end

    test "respects the limit parameter when passed" do
      two_transfers = VCR.use_cassette("stripe/retrieve_destination_records_with_limit") do
        Billing::Stripe::Transfer.list(limit: 2, destination: @destination, destination_currency: @destination_currency)
      end

      assert_equal 2, two_transfers.count
      assert_equal @base_transfers.first.transfer_id, two_transfers.first.transfer_id
      assert_equal @base_transfers[1].transfer_id, two_transfers.last.transfer_id
    end

    test "respects the starting_after parameter when passed" do
      after_transfers = VCR.use_cassette("stripe/retrieve_destination_records_with_starting_after") do
        Billing::Stripe::Transfer.list(starting_after: @base_transfers.first.transfer_id, destination: @destination, destination_currency: @destination_currency)
      end

      assert_equal 9, after_transfers.count
      refute_includes after_transfers.map(&:transfer_id), @base_transfers.first.transfer_id
    end

    test "respects the transfer_group parameter when passed" do
      specific_transfer = VCR.use_cassette("stripe/retrieve_destination_records_with_transfer_group") do
        Billing::Stripe::Transfer.list(transfer_group: @platform_transaction_id, destination: @destination, destination_currency: @destination_currency)
      end

      assert_equal 1, specific_transfer.count
      assert_equal @platform_transaction_id, specific_transfer.first.transfer_group
    end

    test "respects the sponsor filter when passed" do
      sponsor = create(:billing_transaction, platform_transaction_id: "2c92c0fb6fd667e5016fee49e7be61b7").user

      transfers = VCR.use_cassette("stripe/retrieve_destination_records") do
        Billing::Stripe::Transfer.list(destination: @destination, destination_currency: @destination_currency, sponsor: sponsor.login)
      end

      assert_equal 2, transfers.count
    end

    # See: https://github.com/github/sponsors/issues/3321
    test "returns list even when a user has been deleted" do
      @user.destroy!

      transfers = VCR.use_cassette("stripe/retrieve_destination_records") do
        Billing::Stripe::Transfer.list(destination: @destination, destination_currency: @destination_currency)
      end

      assert_equal 11, @base_transfers.count
    end

    test "allows filtering by transfer group instead of destination, and omitting a limit" do
      transfer_group = "2c92c0fb6c99c25e016cb5ec29103370"

      transfers = VCR.use_cassette("zuora/stripe/reverse_transfer") do
        Billing::Stripe::Transfer.list(transfer_group: transfer_group, limit: nil)
      end

      refute_empty transfers
      assert transfers.all? { |xfer| xfer.transfer_group == transfer_group },
        "expected all returned results to have the queried transfer group"
    end
  end

  test "#transfer_url returns the url to view on stripe" do
    transfer = @base_transfers.first
    expected_url = "#{GitHub.stripe_connect_dashboard_base_url}/transfers/#{transfer.transfer_id}"

    assert_equal expected_url, transfer.transfer_url
  end
end
