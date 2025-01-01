# typed: true
# frozen_string_literal: true

require "test_helper"

class Stafftools::Billing::PaymentRecordTest < GitHub::TestCase
  context "#subscription_item_text" do
    test "returns listing and tier name for first Marketplace line item" do
      listing = create(:marketplace_listing)
      listing_plan = create(:marketplace_listing_plan, listing: listing)
      billing_transaction = create(:billing_transaction)
      create(:billing_transaction_line_item, subscribable: listing_plan,
        listing: listing, billing_transaction: billing_transaction)

      payment_record = Stafftools::Billing::PaymentRecord.new(billing_transaction)

      assert_equal "#{listing.name} #{listing_plan.name}", payment_record.subscription_item_text
    end

    test "returns 'Deleted Marketplace Listing' if listing is missing" do
      listing = create(:marketplace_listing)
      listing_plan = create(:marketplace_listing_plan, listing: listing)
      billing_transaction = create(:billing_transaction)
      create(:billing_transaction_line_item, subscribable: listing_plan,
        listing: listing, billing_transaction: billing_transaction)
      listing.destroy
      listing_plan.destroy

      payment_record = Stafftools::Billing::PaymentRecord.new(billing_transaction)

      assert_equal "Deleted Marketplace Listing", payment_record.subscription_item_text
    end
  end

  context "#plan_info" do
    test "describes a recurring sponsorship" do
      sponsorship = create(:sponsorship, :from_org, :with_billing_transaction_and_line_item)
      org = sponsorship.sponsor
      transaction = org.billing_transactions.first
      record = Stafftools::Billing::PaymentRecord.new(transaction)

      assert_equal "Recurring sponsorship", record.plan_info
    end

    test "describes a one-time sponsorship" do
      sponsorship = create(:sponsorship, :one_time, :from_org, :with_billing_transaction_and_line_item)
      org = sponsorship.sponsor
      transaction = org.billing_transactions.first
      record = Stafftools::Billing::PaymentRecord.new(transaction)

      assert_equal "One-time sponsorship", record.plan_info
    end

    test 'describes sponsorship frequency when charge type is "prorate-charge" and subscribable_id is a tier ' do
      sponsorship = create(:sponsorship, :one_time, :from_org)
      tier = sponsorship.tier
      org = sponsorship.sponsor

      transaction = create(:billing_transaction,
        transaction_type: "prorate-charge",
        user: org,
        platform_transaction_id: SecureRandom.hex(3),
        amount_in_cents: tier.monthly_price_in_cents
      )
      sponsors_line_item_attrs = { billing_transaction: transaction, subscribable: tier }
      if sponsors_plan_sub = sponsorship.sponsor.sponsors_plan_subscription
        sponsors_line_item_attrs[:plan_subscription] = sponsors_plan_sub
      end
      create(:billing_transaction_line_item, :sponsors, sponsors_line_item_attrs)

      record = Stafftools::Billing::PaymentRecord.new(transaction)

      assert_equal "One-time sponsorship", record.plan_info
    end
  end

  context "#unique_sponsorship_tier_frequencies" do
    test "returns an empty array when there are no sponsorship line items" do
      transaction = create(:billing_transaction)
      payment_record = Stafftools::Billing::PaymentRecord.new(transaction)

      assert_equal [], payment_record.unique_sponsorship_tier_frequencies
    end

    test "returns unique sponsors tier frequencies when there are sponsorship line items" do
      sponsorship = create(:sponsorship, :from_org, :with_billing_transaction_and_line_item)
      org = sponsorship.sponsor
      transaction = org.billing_transactions.first

      one_time_sponsorship = create(:sponsorship, :from_org, :one_time, sponsor: org)
      create(:billing_transaction_line_item, :sponsors, billing_transaction: transaction, subscribable: one_time_sponsorship.tier)

      payment_record = Stafftools::Billing::PaymentRecord.new(transaction)

      assert_equal %w[recurring one_time], payment_record.unique_sponsorship_tier_frequencies
    end
  end

  context "#sponsorship_tier_summary" do
    test "returns nil if there are no sponsors tier frequencies" do
      billing_transaction = create(:billing_transaction)
      payment_record = Stafftools::Billing::PaymentRecord.new(billing_transaction)

      assert_nil payment_record.sponsorship_tier_summary
    end

    context "when there is only 1 unique sponsors tier frequency" do
      test "returns One-time when the sponsorship is one time" do
        sponsorship = create(:sponsorship, :from_org, :one_time, :with_billing_transaction_and_line_item)
        org = sponsorship.sponsor
        transaction = org.billing_transactions.first
        payment_record = Stafftools::Billing::PaymentRecord.new(transaction)

        assert_equal "One-time", payment_record.sponsorship_tier_summary
      end

      test "returns Recurring when the sponsorship is recurring" do
        sponsorship = create(:sponsorship, :from_org, :with_billing_transaction_and_line_item)
        org = sponsorship.sponsor
        transaction = org.billing_transactions.first
        payment_record = Stafftools::Billing::PaymentRecord.new(transaction)

        assert_equal "Recurring", payment_record.sponsorship_tier_summary
      end
    end

    test "returns 'Multiple' when there are multiple unique sponsors tier frequencies" do
      sponsorship = create(:sponsorship, :from_org, :with_billing_transaction_and_line_item)
      org = sponsorship.sponsor
      transaction = org.billing_transactions.first

      one_time_sponsorship = create(:sponsorship, :from_org, :one_time, sponsor: org)
      create(:billing_transaction_line_item, :sponsors, billing_transaction: transaction, subscribable: one_time_sponsorship.tier)

      payment_record = Stafftools::Billing::PaymentRecord.new(transaction)

      assert_equal "Multiple", payment_record.sponsorship_tier_summary
    end
  end
end
