# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::ReceiptTest < GitHub::BillingTestCase
  include ::Billing::ApiTestHelpers
  include ::Billing::CodespacesUsageHelpers

  fixtures do
    @user = create(:user)
    @org = create :organization, seats: 20
    @now = DateTime.new(2014, 1, 1, 13, 45, 0, "-0800").freeze

    @billing_transaction = create :billing_transaction,
                user: @user,
                plan_name: "Small",
                transaction_id: "bd2gx6",
                amount_in_cents: 12_00,
                plan_price_in_cents: 12_00,
                service_ends_at: @now + 1.month,
                created_at: @now,
                updated_at: @now

    @org_billing_transaction = create :billing_transaction,
                user: @org,
                plan_name: "business",
                transaction_id: "wow777",
                seats_total: 20,
                amount_in_cents: 400_00,
                plan_price_in_cents: 20_00,
                paypal_email: "coolorg-paypal@gmail.com",
                service_ends_at: @now + 1.month,
                created_at: @now,
                updated_at: @now

    @post_munich_now = GitHub::Billing.timezone.parse("2020-04-14").freeze
    @org_billing_transaction_post_munich = create :billing_transaction,
                user: @org,
                plan_name: "business",
                transaction_id: "wow778",
                seats_total: 20,
                amount_in_cents: 400_00,
                plan_price_in_cents: 20_00,
                paypal_email: "coolorg-paypal@gmail.com",
                service_ends_at: @post_munich_now + 1.month,
                created_at: @post_munich_now,
                updated_at: @post_munich_now

    @business_billing_transaction = create :billing_transaction,
      :business_owned,
      plan_name: "business_plus",
      transaction_id: "wow779",
      seats_total: 20,
      amount_in_cents: 400_00,
      plan_price_in_cents: 20_00,
      service_ends_at: @now + 1.month,
      created_at: @now,
      updated_at: @now
  end

  setup do
    @receipt_for_user = ::Billing::Receipt.new(@billing_transaction)
    @receipt_for_org = ::Billing::Receipt.new(@org_billing_transaction)
    @receipt_for_org_post_munich = ::Billing::Receipt.new(@org_billing_transaction_post_munich)
    @receipt_for_business = ::Billing::Receipt.new(@business_billing_transaction)

    GitHub.flipper[:payment_receipt_line_item_format].disable
  end

  include GitHub::BrainTree::TestHelper

  context "#display_tax?" do
    test "returns false when there's no tax items in the transaction" do
      @billing_transaction.tax_items.destroy_all
      @billing_transaction.reload

      refute Billing::Receipt.new(@billing_transaction).display_tax?
    end

    test "returns true when the transaction has tax items and the feature flag is enabled" do
      GitHub.flipper[:tax_line_items].enable
      billing_transaction = create(:billing_transaction, :with_taxed_line_items)

      assert billing_transaction.tax_items.present?
      assert Billing::Receipt.new(billing_transaction).display_tax?
    end
  end

  test "#transaction_id" do
    assert_equal "bd2gx6", @receipt_for_user.transaction_id
    assert_equal "wow777", @receipt_for_org.transaction_id
    assert_equal "wow779", @receipt_for_business.transaction_id
  end

  test "#datetime" do
    assert_equal "2014-01-01 01:45PM PST", @receipt_for_user.purchased_at.strftime("%Y-%m-%d %I:%M%p %Z")
    assert_equal "2014-01-01 01:45PM PST", @receipt_for_org.purchased_at.strftime("%Y-%m-%d %I:%M%p %Z")
    assert_equal "2014-01-01 01:45PM PST", @receipt_for_business.purchased_at.strftime("%Y-%m-%d %I:%M%p %Z")
  end

  test "#amount" do
    assert_equal "$12.00", @receipt_for_user.amount.format
    assert_equal "$400.00", @receipt_for_org.amount.format
    assert_equal "$400.00", @receipt_for_business.amount.format
  end

  test "#service_ends_on" do
    assert_equal "2014-02-01", @receipt_for_user.service_ends_on
    assert_equal "2014-02-01", @receipt_for_org.service_ends_on
    assert_equal "2014-02-01", @receipt_for_business.service_ends_on
  end

  test "#per_seat?" do
    refute @receipt_for_user.per_seat?
    assert @receipt_for_org.per_seat?
    assert @receipt_for_business.per_seat?
  end

  test "#receipt_header" do
    assert_equal "GITHUB RECEIPT - PERSONAL SUBSCRIPTION - #{@user}", @receipt_for_user.receipt_header
    assert_equal "GITHUB RECEIPT - ORGANIZATION SUBSCRIPTION - #{@org}", @receipt_for_org.receipt_header
    assert_equal \
      "GITHUB RECEIPT - ENTERPRISE SUBSCRIPTION - #{@receipt_for_business.billable_entity}",
      @receipt_for_business.receipt_header
  end

  test "#plan_summary" do
    assert_equal "Small", @receipt_for_user.plan_summary

    assert_equal "5 included seats + 15 additional seats ($9/month each)", @receipt_for_org.plan_summary
    assert_equal "Team: 20 seats ($4/month each)", @receipt_for_org_post_munich.plan_summary
    assert_equal "20 seats ($21/month each)", @receipt_for_business.plan_summary
  end

  test "#payment_type" do
    assert_equal "Visa", @receipt_for_user.payment_type
    assert_equal "PayPal account", @receipt_for_org.payment_type
    assert_equal "Visa", @receipt_for_business.payment_type
  end

  test "#payment_identifier" do
    assert_equal "4*** **** **** 1234", @receipt_for_user.payment_identifier
    assert_equal "coolorg-paypal@gmail.com", @receipt_for_org.payment_identifier
    assert_equal "4*** **** **** 1234", @receipt_for_business.payment_identifier
  end

  test "filename contains parameterised account and date of transaction" do
    date = @billing_transaction.created_at.in_billing_timezone.strftime("%Y-%m-%d")
    assert_equal "github-#{@user.login}-receipt-#{date}.pdf", @receipt_for_user.pdf_filename
    assert_equal \
      "github-#{@receipt_for_business.billable_entity.slug}-receipt-#{date}.pdf",
      @receipt_for_business.pdf_filename
  end

  context "data pack purchases" do
    test "shows on receipts when purchased" do
      @billing_transaction.transaction_type  = "prorate-asset-pack-charge"
      @billing_transaction.asset_packs_delta = 1
      @billing_transaction.asset_packs_total = 1
      @billing_transaction.service_ends_at   = (@now + 10.days).beginning_of_day
      receipt = ::Billing::Receipt.new(@billing_transaction)
      assert_equal "1 additional data pack ($5/month each - prorated for 11 days)", receipt.plan_summary
    end

    test "doesn't show if no asset packs" do
      receipt = ::Billing::Receipt.new(@billing_transaction)
      refute_match "data pack", receipt.plan_summary
    end

    test "calcuate proration in billing timezone" do
      @billing_transaction.transaction_type  = "prorate-asset-pack-charge"
      @billing_transaction.asset_packs_delta = 1
      @billing_transaction.asset_packs_total = 1
      @billing_transaction.created_at        = Time.parse "2015-04-22 23:30:00 UTC"
      # 2015-05-22 00:00:00 PDT - which is how we parsed next_billing_date to
      #   set service_ends_at
      @billing_transaction.service_ends_at   = Time.parse "2015-05-22 07:00:00 UTC"
      receipt = ::Billing::Receipt.new(@billing_transaction)
      assert_equal "1 additional data pack ($5/month each - prorated for 31 days)",
        receipt.plan_summary
    end
  end

  context "when the plan has different monthly and yearly pricing" do
    test "it shows the yearly unit cost on the receipt when yearly" do
      transaction = create :billing_transaction,
        renewal_frequency: 1, # yearly
        plan_name: "business_plus",
        transaction_type: "prorate-charge",
        seats_delta: 1
      receipt = ::Billing::Receipt.new(transaction)

      assert_includes receipt.plan_summary, "$#{GitHub::Plan.business_plus.yearly_unit_cost}/year"
    end

    test "it shows the monthly unit cost on the receipt when monthly" do
      transaction = create :billing_transaction,
        renewal_frequency: 0, # monthly
        plan_name: "business_plus",
        transaction_type: "prorate-charge",
        seats_delta: 1
      receipt = ::Billing::Receipt.new(transaction)

      assert_includes receipt.plan_summary, "$21/month"
    end
  end

  context "when the plan on the receipt no longer exists" do
    test "it shows the plan name in the plan summary" do
      transaction = create(:billing_transaction, plan_name: "old")
      receipt = ::Billing::Receipt.new(transaction)

      assert_equal "Old", receipt.plan_summary
    end
  end

  test "it shows 'Pro plan' in the plan summary" do
    transaction = create(:billing_transaction, plan_name: "pro")
    receipt = ::Billing::Receipt.new(transaction)

    assert_equal "Pro", receipt.plan_summary
  end

  context "when upgrading from business to business plus plan" do
    test "it shows the new plan name in the plan summary" do
      transaction = create :billing_transaction,
        plan_name: "business_plus",
        transaction_type: "prorate-switch-to-seat-charge",
        seats_total: 7
      receipt = ::Billing::Receipt.new(transaction)
      transaction.user.enable_feature :business_plus

      assert_equal "Switch to #{GitHub::Plan.business_plus.titleized_display_name} (7 seats)", receipt.plan_summary
    end
  end

  context "when upgrading from repo to business plan" do
    test "it shows the correct plan name when business plus feature enabled" do
      transaction = create :billing_transaction,
        plan_name: "business",
        transaction_type: "prorate-switch-to-seat-charge",
        seats_total: 5
      receipt = ::Billing::Receipt.new(transaction)
      transaction.user.enable_feature :business_plus

      assert_equal "Switch to Team (5 seats)", receipt.plan_summary
    end
  end

  context "when the user has been deleted" do
    test "a receipt can still be generated" do
      transaction = create(:billing_transaction, plan_name: "pro")
      transaction.user.destroy
      transaction = Billing::BillingTransaction.find(transaction.id)

      receipt = Billing::Receipt.new(transaction)

      assert receipt.to_pdf
    end
  end

  context "with Sponsors purchases" do
    test "handles one-time sponsorship without fee" do
      listing = create(:sponsors_listing, :approved, tier_count: 0)
      tier = create(:sponsors_tier, :published, :one_time, sponsors_listing: listing,
        monthly_price_in_cents: 2_00)
      sponsorship = create(:sponsorship, tier: tier)
      transaction = create(:billing_transaction,
        user: sponsorship.sponsor,
        amount_in_cents: tier.monthly_price_in_cents,
        transaction_type: "prorate-charge")
      line_item = create(:billing_transaction_line_item, :sponsors,
        billing_transaction: transaction,
        subscribable: tier)

      receipt = Billing::Receipt.new(transaction)

      assert_equal line_item.to_money, receipt.sponsorship_amount_excluding_fees
      assert_equal line_item.to_money, receipt.sponsorship_amount_including_fees
      assert_equal Billing::Money.zero, receipt.sponsorship_fees_amount
      assert_equal "#{listing.slug.delete_prefix("sponsors-")} - $2 one time", receipt.sponsorship_line_items_text
      assert_equal "", receipt.sponsorship_prorated_message
    end

    test "handles one-time sponsorship with fee" do
      listing = create(:sponsors_listing, :approved, tier_count: 0)
      tier = create(:sponsors_tier, :published, :one_time, sponsors_listing: listing, monthly_price_in_cents: 2_00)
      fee_amount = Sponsorship.fee_for_credit_card_org_sponsorship_at(tier.base_price)
      sponsorship = create(:sponsorship, :from_org, tier: tier)
      transaction = create(:billing_transaction, user: sponsorship.sponsor,
        amount_in_cents: tier.monthly_price_in_cents + fee_amount.cents)
      non_fee_line_item = create(:billing_transaction_line_item, :sponsors, billing_transaction: transaction,
        subscribable: tier)
      fee_line_item = create(:billing_transaction_line_item, :sponsors_fee, billing_transaction: transaction,
        amount_in_cents: fee_amount.cents, subscribable: tier)

      receipt = Billing::Receipt.new(transaction)

      assert_equal non_fee_line_item.to_money, receipt.sponsorship_amount_excluding_fees,
        "should not include fees in Sponsorship Amount line"
      assert_equal fee_line_item.to_money, receipt.sponsorship_fees_amount
      assert_equal non_fee_line_item.to_money + fee_line_item.to_money, receipt.sponsorship_amount_including_fees
      assert_equal "#{listing.slug.delete_prefix("sponsors-")} - $2 one time\n#{listing.slug.delete_prefix("sponsors-")} - $2 one time - fee ($0.12)",
        receipt.sponsorship_line_items_text
    end

    test "handles recurring sponsorship without fee" do
      listing = create(:sponsors_listing, :approved, tier_count: 0)
      tier = create(:sponsors_tier, :published, sponsors_listing: listing,
        monthly_price_in_cents: 5_00)
      sponsorship = create(:sponsorship, tier: tier)
      transaction = create(:billing_transaction, user: sponsorship.sponsor,
        amount_in_cents: tier.monthly_price_in_cents)
      line_item = create(:billing_transaction_line_item, :sponsors,
        billing_transaction: transaction,
        subscribable: tier)

      receipt = Billing::Receipt.new(transaction)

      assert_equal line_item.to_money, receipt.sponsorship_amount_excluding_fees
      assert_equal line_item.to_money, receipt.sponsorship_amount_including_fees
      assert_equal Billing::Money.zero, receipt.sponsorship_fees_amount
      assert_equal "#{listing.slug.delete_prefix("sponsors-")} - $5 a month", receipt.sponsorship_line_items_text
    end

    test "handles recurring sponsorship with fee" do
      listing = create(:sponsors_listing, :approved, tier_count: 0)
      tier = create(:sponsors_tier, :published, sponsors_listing: listing,
        monthly_price_in_cents: 5_00)
      fee_amount = Sponsorship.fee_for_credit_card_org_sponsorship_at(tier.base_price)
      sponsorship = create(:sponsorship, :from_org, tier: tier)
      transaction = create(:billing_transaction, user: sponsorship.sponsor,
        amount_in_cents: tier.monthly_price_in_cents + fee_amount.cents)
      non_fee_line_item = create(:billing_transaction_line_item, :sponsors, billing_transaction: transaction,
        subscribable: tier)
      fee_line_item = create(:billing_transaction_line_item, :sponsors_fee, billing_transaction: transaction,
        subscribable: tier, amount_in_cents: fee_amount.cents)

      receipt = Billing::Receipt.new(transaction)

      assert_equal non_fee_line_item.to_money, receipt.sponsorship_amount_excluding_fees,
        "should not include fees in Sponsorship Amount line"
      assert_equal non_fee_line_item.to_money + fee_line_item.to_money, receipt.sponsorship_amount_including_fees
      assert_equal fee_line_item.to_money, receipt.sponsorship_fees_amount
      assert_equal "#{listing.slug.delete_prefix("sponsors-")} - $5 a month\n#{listing.slug.delete_prefix("sponsors-")} - $5 a month - fee ($0.30)",
        receipt.sponsorship_line_items_text
    end

    test "still mentions the fee when the formatted fee amount is a substring of the total sponsorship amount" do
      listing = create(:sponsors_listing, :approved, tier_count: 0)
      tier = create(:sponsors_tier, :published, sponsors_listing: listing,
        monthly_price_in_cents: 18_00)
      sponsorship = create(:sponsorship, :from_org, tier: tier)
      transaction = create(:billing_transaction, user: sponsorship.sponsor, amount_in_cents: 17_66)
      non_fee_line_item = create(:billing_transaction_line_item, :sponsors, billing_transaction: transaction,
        subscribable: tier, amount_in_cents: 16_66)
      fee_line_item = create(:billing_transaction_line_item, :sponsors_fee, billing_transaction: transaction,
        subscribable: tier, amount_in_cents: 1_00)

      receipt = Billing::Receipt.new(transaction)

      assert_equal non_fee_line_item.to_money, receipt.sponsorship_amount_excluding_fees,
        "should not include fees in Sponsorship Amount line"
      assert_equal non_fee_line_item.to_money + fee_line_item.to_money, receipt.sponsorship_amount_including_fees
      assert_equal fee_line_item.to_money, receipt.sponsorship_fees_amount
      assert_equal "#{listing.slug.delete_prefix("sponsors-")} - $18 a month ($16.66)\n#{listing.slug.delete_prefix("sponsors-")} - $18 a month - fee ($1.00)",
        receipt.sponsorship_line_items_text
    end
  end

  context "with Copilot purchase" do
    test "displays correct line item information when there's combined Copilot line items" do
      # Our log_recurring_charge code currently combines multiple invoice items from Zuora
      # into a single line item in our billing transaction based on the subscribable
      # In this case we have
      # Invoice A
      #   Invoice item - Copilot monthly $10
      # Invoice B
      #   Invoice item - Copilot monthly -$10
      #   Invoice item - Copilot yearly $90
      #
      # This gets translated to
      # Billing transaction
      #   Line item - Copilot monthly $0
      #   Line item - Copilot yearly $100
      #
      # Until we fix this, we have to account for this edge case. We do this by selecting the maximum
      # amount line item as the one to use on the receipt. This does not happen the other way around
      copilot_monthly_product_uuid = create(:billing_product_uuid, :copilot, billing_cycle: :month)
      copilot_yearly_product_uuid = create(:billing_product_uuid, :copilot, billing_cycle: :year)
      plan_subscription = create(:billing_plan_subscription, :zuora)
      plan_user = plan_subscription.user

      transaction = create(:billing_transaction, user: plan_user,
        amount_in_cents: 100_00)

      create(:billing_transaction_line_item,
        billing_transaction: transaction,
        subscribable: copilot_monthly_product_uuid,
        amount_in_cents: 0,
        quantity: 0,
        description: "GitHub Copilot - month",
      )
      create(:billing_transaction_line_item,
        billing_transaction: transaction,
        subscribable: copilot_yearly_product_uuid,
        amount_in_cents: 100_00,
        quantity: 1,
        description: "GitHub Copilot - year",
      )

      receipt = Billing::Receipt.new(transaction)
      assert_equal Billing::Money.new(100_00), receipt.copilot_amount
      assert_equal "$100.00/year", receipt.copilot_formatted_amount
    end

    test "handles monthly purchase" do
      copilot_monthly_product_uuid = create(:billing_product_uuid, :copilot, billing_cycle: :month)
      plan_subscription = create(:billing_plan_subscription, :zuora)
      plan_user = plan_subscription.user

      subscription_item = create(:billing_subscription_item, :paid,
        plan_subscription: plan_subscription,
        subscribable: copilot_monthly_product_uuid
      )

      transaction = create(:billing_transaction, user: plan_user,
        amount_in_cents: 7_50)

      line_item = create(:billing_transaction_line_item,
        billing_transaction: transaction,
        subscribable: copilot_monthly_product_uuid,
        amount_in_cents: 5_00,
        quantity: 1,
        description: "GitHub Copilot",
        subscribable_type: Billing::ProductUUID.name
      )

      receipt = Billing::Receipt.new(transaction)
      assert_equal Billing::Money.new(5_00), receipt.copilot_amount

      # (7_50 transaction amount - 5_00 copilot amount)
      assert_equal Billing::Money.new(2_50), receipt.plan_amount
      assert_equal Billing::Money.new(7_50), receipt.amount
    end

    test "handles monthly purchase with proration" do
      copilot_monthly_product_uuid = create(:billing_product_uuid, :copilot, billing_cycle: :month)
      plan_subscription = create(:billing_plan_subscription, :zuora)
      plan_user = plan_subscription.user

      subscription_item = create(:billing_subscription_item, :paid,
        plan_subscription: plan_subscription,
        subscribable: copilot_monthly_product_uuid
      )

      transaction = create(:billing_transaction, user: plan_user,
        amount_in_cents: 7_50, prorated_days: 12, transaction_type: "prorate-charge")

      line_item = create(:billing_transaction_line_item,
        billing_transaction: transaction,
        subscribable: copilot_monthly_product_uuid,
        amount_in_cents: 5_00,
        quantity: 1,
        description: "GitHub Copilot",
        subscribable_type: Billing::ProductUUID.name
      )

      receipt = Billing::Receipt.new(transaction)
      assert_equal Billing::Money.new(5_00), receipt.copilot_amount

      # (7_50 transaction amount - 5_00 copilot amount)
      assert_equal Billing::Money.new(2_50), receipt.plan_amount
      assert_equal Billing::Money.new(7_50), receipt.amount
      assert_equal "$5.00 ($10/month - prorated for 12 days)", receipt.copilot_formatted_amount
    end

    test "does not show prorated message when the amount charged is the same as the base price" do
      copilot_yearly_product_uuid = create(:billing_product_uuid, :copilot, billing_cycle: :year)
      plan_subscription = create(:billing_plan_subscription, :zuora)
      plan_user = plan_subscription.user

      subscription_item = create(:billing_subscription_item, :paid,
        plan_subscription: plan_subscription,
        subscribable: copilot_yearly_product_uuid
      )

      transaction = create(:billing_transaction, user: plan_user,
        amount_in_cents: 100_00, prorated_days: 365, transaction_type: "prorate-charge")

      line_item = create(:billing_transaction_line_item,
        billing_transaction: transaction,
        subscribable: copilot_yearly_product_uuid,
        amount_in_cents: 100_00,
        quantity: 1,
        description: "GitHub Copilot",
        subscribable_type: Billing::ProductUUID.name
      )

      receipt = Billing::Receipt.new(transaction)
      assert_equal "$100.00/year", receipt.copilot_formatted_amount
    end
  end

  context "with advanced security purchase" do
    test "handles monthly purchase" do
      advanced_security_monthly_product_uuid = create(:billing_product_uuid, :advanced_security, billing_cycle: :month)
      plan_subscription = create(:billing_plan_subscription, :zuora)
      plan_user = plan_subscription.user

      subscription_item = create(:billing_subscription_item, :paid,
        plan_subscription: plan_subscription,
        subscribable: advanced_security_monthly_product_uuid
      )

      transaction = create(:billing_transaction, user: plan_user,
        amount_in_cents: 55_00)

      line_item = create(:billing_transaction_line_item,
          billing_transaction: transaction,
          subscribable: advanced_security_monthly_product_uuid,
          amount_in_cents: 49_00,
          quantity: 1,
          description: "GitHub Advanced Security",
          subscribable_type: Billing::ProductUUID.name
        )

      receipt = Billing::Receipt.new(transaction)
      assert_equal Billing::Money.new(49_00), receipt.advanced_security_amount

      # (55_00 transaction amount - 49_00 ghas amount)
      assert_equal Billing::Money.new(6_00), receipt.plan_amount
      assert_equal Billing::Money.new(55_00), receipt.amount
      assert_equal "1 seat ($49/month each)", receipt.advanced_security_formatted_amount
    end

    test "handles monthly purchase with multiple seats" do
      advanced_security_monthly_product_uuid = create(:billing_product_uuid, :advanced_security, billing_cycle: :month)
      plan_subscription = create(:billing_plan_subscription, :zuora)
      plan_user = plan_subscription.user

      subscription_item = create(:billing_subscription_item, :paid,
        plan_subscription: plan_subscription,
        subscribable: advanced_security_monthly_product_uuid
      )

      transaction = create(:billing_transaction, user: plan_user,
        amount_in_cents: 202_00)

      line_item = create(:billing_transaction_line_item,
          billing_transaction: transaction,
          subscribable: advanced_security_monthly_product_uuid,
          amount_in_cents: 196_00,
          quantity: 4,
          description: "GitHub Advanced Security",
          subscribable_type: Billing::ProductUUID.name
        )

      receipt = Billing::Receipt.new(transaction)
      assert_equal Billing::Money.new(196_00), receipt.advanced_security_amount

      # (55_00 transaction amount - 49_00 ghas amount)
      assert_equal Billing::Money.new(6_00), receipt.plan_amount
      assert_equal Billing::Money.new(202_00), receipt.amount
      assert_equal "4 seats ($49/month each)", receipt.advanced_security_formatted_amount
    end

    test "handles monthly purchase with proration" do
      advanced_security_monthly_product_uuid = create(:billing_product_uuid, :advanced_security, billing_cycle: :month)
      plan_subscription = create(:billing_plan_subscription, :zuora)
      plan_user = plan_subscription.user

      subscription_item = create(:billing_subscription_item, :paid,
        plan_subscription: plan_subscription,
        subscribable: advanced_security_monthly_product_uuid
      )

      transaction = create(:billing_transaction, user: plan_user,
        amount_in_cents: 55_00, prorated_days: 12, transaction_type: "prorate-charge")

      line_item = create(:billing_transaction_line_item,
          billing_transaction: transaction,
          subscribable: advanced_security_monthly_product_uuid,
          amount_in_cents: 49_00,
          quantity: 1,
          description: "GitHub Advanced Security",
          subscribable_type: Billing::ProductUUID.name
        )

      receipt = Billing::Receipt.new(transaction)
      assert_equal Billing::Money.new(49_00), receipt.advanced_security_amount

      # (55_00 transaction amount - 49_00 advanced_security amount)
      assert_equal Billing::Money.new(6_00), receipt.plan_amount
      assert_equal Billing::Money.new(55_00), receipt.amount
      assert_equal "1 seat ($49/month each - prorated for 12 days)", receipt.advanced_security_formatted_amount
    end

    test "handles multiple subscribable purchases" do
      copilot_monthly_product_uuid = create(:billing_product_uuid, :copilot, billing_cycle: :month)
      advanced_security_monthly_product_uuid = create(:billing_product_uuid, :advanced_security, billing_cycle: :month)

      plan_subscription = create(:billing_plan_subscription, :zuora)
      plan_user = plan_subscription.user

      copilot_subscription_item = create(:billing_subscription_item, :paid,
        plan_subscription: plan_subscription,
        subscribable: copilot_monthly_product_uuid
      )

      ghas_subscription_item = create(:billing_subscription_item, :paid,
        plan_subscription: plan_subscription,
        subscribable: advanced_security_monthly_product_uuid
      )

      transaction = create(:billing_transaction, user: plan_user,
        amount_in_cents: 60_00)

      copilot_line_item = create(:billing_transaction_line_item,
          billing_transaction: transaction,
          subscribable: copilot_monthly_product_uuid,
          amount_in_cents: 5_00,
          quantity: 1,
          description: "GitHub Copilot",
          subscribable_type: Billing::ProductUUID.name
        )

      ghas_line_item = create(:billing_transaction_line_item,
          billing_transaction: transaction,
          subscribable: advanced_security_monthly_product_uuid,
          amount_in_cents: 49_00,
          quantity: 1,
          description: "GitHub Advanced Security",
          subscribable_type: Billing::ProductUUID.name
        )

      receipt = Billing::Receipt.new(transaction)

      assert_equal Billing::Money.new(6_00), receipt.plan_amount
      assert_equal Billing::Money.new(60_00), receipt.amount
      assert_equal Billing::Money.new(5_00), receipt.copilot_amount
      assert_equal Billing::Money.new(49_00), receipt.advanced_security_amount
    end
  end

  context "with marketplace purchases" do
    test "it shows the listing name and plan name" do
      listing = create :marketplace_listing, :verified,
        name: "TravisCI"
      listing_plan = create :marketplace_listing_plan,
        listing: listing,
        name: "Standard"
      line_item = create :billing_transaction_line_item,
        subscribable: listing_plan,
        listing: listing,
        amount_in_cents: 4_50
      transaction = line_item.billing_transaction

      receipt = Billing::Receipt.new(transaction)

      assert_equal "TravisCI - Standard", receipt.marketplace_line_items_text
      assert_equal Billing::Money.new(0), receipt.actions_amount
      assert_equal Billing::Money.new(4_50), receipt.marketplace_amount

      # 7_00 (transaction amount) - 0 (actions_amount) - 4_50 (martketplace_amount)
      assert_equal Billing::Money.new(2_50), receipt.plan_amount

      assert_equal Billing::Money.new(7_00), receipt.amount
    end

    test "it segments sponsorable and non_sponsorable marketplace items" do
      mp_listing = create :marketplace_listing, :verified,
        name: "TravisCI"
      mp_listing_plan = create :marketplace_listing_plan,
        listing: mp_listing,
        name: "Standard"
      mp_line_item = create :billing_transaction_line_item,
        subscribable: mp_listing_plan,
        listing: mp_listing,
        amount_in_cents: 4_50

      transaction = mp_line_item.billing_transaction
      transaction.update_column(:amount_in_cents, 21_50)

      sponsorship_listing = create(:sponsors_listing, :with_tier)
      sponsorship_tier = sponsorship_listing.default_tier
      create :billing_transaction_line_item,
        subscribable: sponsorship_tier,
        listing: sponsorship_listing,
        amount_in_cents: 10_00,
        billing_transaction: transaction

      transaction.reload

      receipt = Billing::Receipt.new(transaction)

      assert_equal "TravisCI - Standard", receipt.marketplace_line_items_text
      assert_equal Billing::Money.new(0), receipt.actions_amount
      assert_equal Billing::Money.new(4_50), receipt.marketplace_amount

      assert_equal Billing::Money.new(10_00), receipt.sponsorship_amount_excluding_fees

      # 21_50 (transaction amount) - 0 (actions_amount) - 4_50 (martketplace_amount) - 10_00 (sponsorship amoount)
      assert_equal Billing::Money.new(7_00), receipt.plan_amount

      assert_equal Billing::Money.new(21_50), receipt.amount
    end

    test "works with an expensive marketplace purchase" do
      listing = create(:marketplace_listing)
      listing_plan = create(:marketplace_listing_plan, listing: listing)
      line_item = create :billing_transaction_line_item,
        subscribable: listing_plan,
        listing: listing,
        amount_in_cents: 24_50
      transaction = line_item.billing_transaction

      receipt = Billing::Receipt.new(transaction)

      assert_equal Billing::Money.new(0), receipt.actions_amount
      assert_equal Billing::Money.new(24_50), receipt.marketplace_amount
      assert_equal Billing::Money.new(0), receipt.plan_amount
    end
  end

  context "with usages" do
    test "works with actions usage items that only uses included usage with plan" do
      transaction = create(:billing_transaction,
        plan_name: "pro",
        amount_in_cents: 7_00)
      create :billing_transaction_line_item,
        :actions_private_usage,
        quantity: 10,
        amount_in_cents: 0,
        billing_transaction: transaction

      receipt = Billing::Receipt.new(transaction)

      actions_text = T.must(receipt.actions_line_items_text).split("\n")

      assert_equal "10 of 3000 included private minutes $0.00 USD", actions_text[0]
      assert_equal Billing::Money.new(0), receipt.actions_amount

      # 7_00 (transaction amount) - 0 (actions_amount) - 0 (marketplace_amount)
      assert_equal Billing::Money.new(7_00), receipt.plan_amount

      assert_equal Billing::Money.new(7_00), receipt.amount
    end

    test "works with actions usage items that only uses free usage without plan" do
      listing = create(:marketplace_listing)
      transaction = create(:billing_transaction,
        plan_name: nil,
        amount_in_cents: 2_50)
      create :billing_transaction_line_item,
        subscribable: create(:marketplace_listing_plan, listing: listing),
        listing: listing,
        amount_in_cents: 2_50,
        billing_transaction: transaction
      create :billing_transaction_line_item,
        :actions_private_usage,
        quantity: 10,
        amount_in_cents: 0,
        billing_transaction: transaction

      exception = RuntimeError.new("Missing plan_name in billing transaction with actions usage")
      Failbot.stubs(:report)
      Failbot.expects(:report).with(exception, { "gh.billing.transaction.id" => transaction.id })

      receipt = Billing::Receipt.new(transaction)

      actions_text = T.must(receipt.actions_line_items_text).split("\n")

      # No plan to calculate total minutes - shows all as included.
      assert_equal "10 included private minutes $0.00 USD", actions_text[0]

      assert_equal Billing::Money.new(0), receipt.actions_amount
      assert_equal Billing::Money.new(2_50), receipt.marketplace_amount
      assert_equal Billing::Money.new(2_50), receipt.amount
    end

    test "works with actions usage items with usage overages" do
      transaction = create(:billing_transaction,
        amount_in_cents: 10_50)

      listing = create(:marketplace_listing)
      create :billing_transaction_line_item,
        subscribable: create(:marketplace_listing_plan, listing: listing),
        listing: listing,
        amount_in_cents: 2_50,
        billing_transaction: transaction

      create :billing_transaction_line_item,
        :actions_private_usage,
        quantity: 3_000,
        amount_in_cents: 0,
        billing_transaction: transaction
      create :billing_transaction_line_item,
        :actions_private_usage,
        quantity: 100,
        amount_in_cents: 100,
        billing_transaction: transaction

      receipt = Billing::Receipt.new(transaction)

      actions_text = T.must(receipt.actions_line_items_text).split("\n")

      assert_includes(actions_text, "3000 included private minutes $0.00 USD")
      assert_includes(actions_text, "100 additional private minutes $1.00 USD")

      assert_equal Billing::Money.new(1_00), receipt.actions_amount
      assert_equal Billing::Money.new(2_50), receipt.marketplace_amount

      # 10_50 (transaction amount) - 1_00 (actions_amount) - 2_50 (marketplace_amount)
      assert_equal Billing::Money.new(7_00), receipt.plan_amount

      assert_equal Billing::Money.new(10_50), receipt.amount
    end

    test "includes actions usage text only for repo visibility that has usage" do
      transaction = create(:billing_transaction,
        plan_name: "pro",
        amount_in_cents: 7_80)

      # Only private actions usage
      create :billing_transaction_line_item,
        :actions_private_usage,
        quantity: 3_000,
        amount_in_cents: 0,
        billing_transaction: transaction
      create :billing_transaction_line_item,
        :actions_private_usage,
        quantity: 100,
        amount_in_cents: 80,
        billing_transaction: transaction

      receipt = Billing::Receipt.new(transaction)

      actions_text = T.must(receipt.actions_line_items_text).split("\n")

      assert_includes(actions_text, "3000 included private minutes $0.00 USD")
      assert_includes(actions_text, "100 additional private minutes $0.80 USD")

      assert_equal Billing::Money.new(80), receipt.actions_amount

      # 7_80 (transaction amount) - 80 (actions_amount)
      assert_equal Billing::Money.new(7_00), receipt.plan_amount

      assert_equal Billing::Money.new(7_80), receipt.amount
    end

    test "works with actions custom runner usage overages" do
      transaction = create(:billing_transaction,
        amount_in_cents: 9_75,
        plan_name: "pro")

      create :billing_transaction_line_item,
        :actions_8_core,
        quantity: 100,
        amount_in_cents: 30,
        billing_transaction: transaction
      create :billing_transaction_line_item,
        :actions_16_core,
        quantity: 10,
        amount_in_cents: 60,
        billing_transaction: transaction
      create :billing_transaction_line_item,
        :actions_macos_12_core,
        quantity: 20,
        amount_in_cents: 100,
        billing_transaction: transaction
      create :billing_transaction_line_item,
        :actions_macos_8_core,
        quantity: 20,
        amount_in_cents: 100,
        billing_transaction: transaction
      create :billing_transaction_line_item,
        :actions_macos_large,
        quantity: 1,
        amount_in_cents: 5,
        billing_transaction: transaction
      create :billing_transaction_line_item,
        :actions_macos_xlarge,
        quantity: 2,
        amount_in_cents: 10,
        billing_transaction: transaction
      create :billing_transaction_line_item,
        :actions_linux_4_core_gpu,
        quantity: 100,
        amount_in_cents: 7_00,
        billing_transaction: transaction
      create :billing_transaction_line_item,
        :actions_windows_4_core_gpu,
        quantity: 100,
        amount_in_cents: 14_00,
        billing_transaction: transaction
      create :billing_transaction_line_item,
        :actions_linux_2_core_arm,
        quantity: 100,
        amount_in_cents: 80,
        billing_transaction: transaction
      create :billing_transaction_line_item,
        :actions_linux_4_core_arm,
        quantity: 100,
        amount_in_cents: 1_60,
        billing_transaction: transaction
      create :billing_transaction_line_item,
        :actions_linux_8_core_arm,
        quantity: 100,
        amount_in_cents: 3_20,
        billing_transaction: transaction
      create :billing_transaction_line_item,
        :actions_linux_16_core_arm,
        quantity: 100,
        amount_in_cents: 6_40,
        billing_transaction: transaction
      create :billing_transaction_line_item,
        :actions_linux_32_core_arm,
        quantity: 100,
        amount_in_cents: 12_80,
        billing_transaction: transaction
      create :billing_transaction_line_item,
        :actions_linux_64_core_arm,
        quantity: 100,
        amount_in_cents: 25_60,
        billing_transaction: transaction
      create :billing_transaction_line_item,
        :actions_windows_2_core_arm,
        quantity: 100,
        amount_in_cents: 1_60,
        billing_transaction: transaction
      create :billing_transaction_line_item,
        :actions_windows_4_core_arm,
        quantity: 100,
        amount_in_cents: 3_20,
        billing_transaction: transaction
      create :billing_transaction_line_item,
        :actions_windows_8_core_arm,
        quantity: 100,
        amount_in_cents: 6_40,
        billing_transaction: transaction
      create :billing_transaction_line_item,
        :actions_windows_16_core_arm,
        quantity: 100,
        amount_in_cents: 12_80,
        billing_transaction: transaction
      create :billing_transaction_line_item,
        :actions_windows_32_core_arm,
        quantity: 100,
        amount_in_cents: 25_60,
        billing_transaction: transaction
      create :billing_transaction_line_item,
        :actions_windows_64_core_arm,
        quantity: 100,
        amount_in_cents: 51_20,
        billing_transaction: transaction
      create :billing_transaction_line_item,
        :actions_linux_2_core_advanced,
        quantity: 100,
        amount_in_cents: 80,
        billing_transaction: transaction
      create :billing_transaction_line_item,
        :actions_windows_2_core_advanced,
        quantity: 100,
        amount_in_cents: 1_60,
        billing_transaction: transaction

      receipt = Billing::Receipt.new(transaction)
      runners_text = T.must(receipt.actions_line_items_text).split("\n")

      assert_includes(runners_text, "100 additional minutes (8 core) $0.30 USD")
      assert_includes(runners_text, "10 additional minutes (16 core) $0.60 USD")
      assert_includes(runners_text, "20 additional minutes (12 core) $1.00 USD")
      assert_includes(runners_text, "20 additional minutes (8 core) $1.00 USD")

      assert_includes(runners_text, "1 additional minute (macOS Large) $0.05 USD")
      assert_includes(runners_text, "2 additional minutes (macOS XLarge) $0.10 USD")

      assert_includes(runners_text, "100 additional minutes (Ubuntu GPU 4 core) $7.00 USD")
      assert_includes(runners_text, "100 additional minutes (Windows GPU 4 core) $14.00 USD")

      assert_includes(runners_text, "100 additional minutes (Ubuntu ARM 2 core) $0.80 USD")
      assert_includes(runners_text, "100 additional minutes (Ubuntu ARM 4 core) $1.60 USD")
      assert_includes(runners_text, "100 additional minutes (Ubuntu ARM 8 core) $3.20 USD")
      assert_includes(runners_text, "100 additional minutes (Ubuntu ARM 16 core) $6.40 USD")
      assert_includes(runners_text, "100 additional minutes (Ubuntu ARM 32 core) $12.80 USD")
      assert_includes(runners_text, "100 additional minutes (Ubuntu ARM 64 core) $25.60 USD")

      assert_includes(runners_text, "100 additional minutes (Windows ARM 2 core) $1.60 USD")
      assert_includes(runners_text, "100 additional minutes (Windows ARM 4 core) $3.20 USD")
      assert_includes(runners_text, "100 additional minutes (Windows ARM 8 core) $6.40 USD")
      assert_includes(runners_text, "100 additional minutes (Windows ARM 16 core) $12.80 USD")
      assert_includes(runners_text, "100 additional minutes (Windows ARM 32 core) $25.60 USD")
      assert_includes(runners_text, "100 additional minutes (Windows ARM 64 core) $51.20 USD")

      assert_includes(runners_text, "100 additional minutes (Ubuntu Advanced 2 core) $0.80 USD")
      assert_includes(runners_text, "100 additional minutes (Windows Advanced 2 core) $1.60 USD")

      assert_equal Billing::Money.new(177_65), receipt.actions_amount
      assert_equal Billing::Money.new(0), receipt.plan_amount
      assert_equal Billing::Money.new(9_75), receipt.amount
    end

    test "does not display actions usage overages when quantity and cost are zero" do
      transaction = create(:billing_transaction,
        plan_name: "pro",
        amount_in_cents: 0)

      # Only private actions usage
      create :billing_transaction_line_item,
        :actions_8_core,
        quantity: 100,
        amount_in_cents: 30,
        billing_transaction: transaction
      create :billing_transaction_line_item,
        :actions_16_core,
        quantity: 0,
        amount_in_cents: 0,
        billing_transaction: transaction

      receipt = Billing::Receipt.new(transaction)
      receipt.billable_entity.enable_feature(:filter_zero_value_line_items)

      actions_text = T.must(receipt.actions_line_items_text).split("\n")

      # Second line item should be omitted
      assert_equal 1, actions_text.size
      assert_includes(actions_text, "100 additional minutes (8 core) $0.30 USD")

      assert_equal Billing::Money.new(0_36), receipt.actions_amount
      assert_equal Billing::Money.new(0), receipt.plan_amount
      assert_equal Billing::Money.new(0), receipt.amount
    end

    test "does not display actions custom runner usage overages with 0 amount" do
      transaction = create(:billing_transaction,
        amount_in_cents: 9_75,
        plan_name: "pro")

      create :billing_transaction_line_item,
        :actions_8_core,
        quantity: 0,
        amount_in_cents: 0,
        billing_transaction: transaction
      create :billing_transaction_line_item,
        :actions_macos_12_core,
        quantity: 0,
        amount_in_cents: 0,
        billing_transaction: transaction
      create :billing_transaction_line_item,
        :actions_macos_8_core,
        quantity: 0,
        amount_in_cents: 0,
        billing_transaction: transaction
      create :billing_transaction_line_item,
        :actions_16_core,
        quantity: 10,
        amount_in_cents: 60,
        billing_transaction: transaction

      receipt = Billing::Receipt.new(transaction)
      runners_text = T.must(receipt.actions_line_items_text).split("\n")
      assert_equal 1, runners_text.size
      assert_equal "10 additional minutes (16 core) $0.60 USD", runners_text[0]

      assert_equal Billing::Money.new(60), receipt.actions_amount
    end

    test "works with packages registry data transfer usage items that only uses included usage with plan" do
      transaction = create(:billing_transaction,
        plan_name: "pro",
        amount_in_cents: 7_00)
      create :billing_transaction_line_item,
        :package_registry_data_usage,
        quantity: 3,
        amount_in_cents: 0,
        billing_transaction: transaction

      receipt = Billing::Receipt.new(transaction)

      packages_data_text = T.must(receipt.packages_transfer_line_items_text).split("\n")

      assert_equal "3GB of #{GitHub::Plan.pro.package_registry_included_bandwidth}GB included data transfer out $0.00 USD", packages_data_text[0]
      assert_equal Billing::Money.new(0), receipt.package_registry_transfer_amount

      # 7_00 (transaction_amount) - 0 (package_registry_transfer_amount) - 0 (marketplace_amount)
      assert_equal Billing::Money.new(7_00), receipt.plan_amount

      assert_equal Billing::Money.new(7_00), receipt.amount
    end

    test "works with packages registry data transfer usage items that only uses free usage without plan" do
      listing = create(:marketplace_listing)
      transaction = create(:billing_transaction,
        plan_name: nil,
        amount_in_cents: 2_50)
      create :billing_transaction_line_item,
        subscribable: create(:marketplace_listing_plan, listing: listing),
        listing: listing,
        amount_in_cents: 2_50,
        billing_transaction: transaction
      create :billing_transaction_line_item,
        :package_registry_data_usage,
        quantity: 3,
        amount_in_cents: 0,
        billing_transaction: transaction

      exception = RuntimeError.new("Missing plan_name in billing transaction with package registry transfer usage")
      Failbot.stubs(:report)
      Failbot.expects(:report).with(exception, { "gh.billing.transaction.id" => transaction.id })

      receipt = Billing::Receipt.new(transaction)

      packages_data_text = T.must(receipt.packages_transfer_line_items_text).split("\n")

      # No plan to calculate total minutes - shows as included.
      assert_equal "3GB included data transfer out $0.00 USD", packages_data_text[0]
      assert_equal Billing::Money.new(0), receipt.package_registry_transfer_amount

      assert_equal Billing::Money.new(0), receipt.package_registry_transfer_amount
      assert_equal Billing::Money.new(2_50), receipt.marketplace_amount
      assert_equal Billing::Money.new(2_50), receipt.amount
    end

    test "works with package registry transfer items with usage overages" do
      transaction = create(:billing_transaction,
        amount_in_cents: 11_00)
      listing = create(:marketplace_listing)
      create :billing_transaction_line_item,
        subscribable: create(:marketplace_listing_plan, listing: listing),
        listing: listing,
        amount_in_cents: 2_50,
        billing_transaction: transaction

      create :billing_transaction_line_item,
        :package_registry_data_usage,
        quantity: 5,
        amount_in_cents: 0,
        billing_transaction: transaction
      create :billing_transaction_line_item,
        :package_registry_data_usage,
        quantity: 3,
        amount_in_cents: 1_50,
        billing_transaction: transaction

      receipt = Billing::Receipt.new(transaction)

      packages_data_text = T.must(receipt.packages_transfer_line_items_text).split("\n")

      assert_includes(packages_data_text, "5GB included data transfer out $0.00 USD")
      assert_includes(packages_data_text, "3GB additional data transfer out $1.50 USD")

      assert_equal Billing::Money.new(1_50), receipt.package_registry_transfer_amount
      assert_equal Billing::Money.new(2_50), receipt.marketplace_amount

      # 11_00 (transaction amount) - 1_50 (package_registry_transfer_amount) - 2_50 (marketplace_amount)
      assert_equal Billing::Money.new(7_00), receipt.plan_amount

      assert_equal Billing::Money.new(11_00), receipt.amount
    end

    test "does not display packages registry data transfer usage items when quantity and cost are zero" do
      transaction = create(:billing_transaction,
        amount_in_cents: 0)
      create :billing_transaction_line_item,
        :package_registry_data_usage,
        quantity: 5,
        amount_in_cents: 1_50,
        billing_transaction: transaction
      create :billing_transaction_line_item,
        :package_registry_data_usage,
        quantity: 0,
        amount_in_cents: 0,
        billing_transaction: transaction

      receipt = Billing::Receipt.new(transaction)
      receipt.billable_entity.enable_feature(:filter_zero_value_line_items)

      packages_data_text = T.must(receipt.packages_transfer_line_items_text).split("\n")

      assert_equal 1, packages_data_text.size
      assert_includes(packages_data_text, "5GB additional data transfer out $1.50 USD")

      assert_equal Billing::Money.new(1_50), receipt.package_registry_transfer_amount
      assert_equal Billing::Money.new(0), receipt.plan_amount
      assert_equal Billing::Money.new(0), receipt.amount
    end

    test "works with shared storage usage items that only uses included usage with plan" do
      transaction = create(:billing_transaction,
        plan_name: "pro",
        amount_in_cents: 7_00)
      create :billing_transaction_line_item,
        :shared_storage,
        quantity: 380_928, # Comment what this means
        amount_in_cents: 0,
        billing_transaction: transaction

      receipt = Billing::Receipt.new(transaction)

      shared_storage_text = T.must(receipt.shared_storage_line_items_text).split("\n")

      assert_equal "0.5GB of #{(GitHub::Plan.pro.shared_storage_included_megabytes.megabytes / 1.gigabytes.to_f).round(2)}GB included storage $0.00 USD", shared_storage_text[0]
      assert_equal Billing::Money.new(0), receipt.shared_storage_amount

      # 7_00 (transaction_amount) - 0 (package_registry_transfer_amount) - 0 (marketplace_amount)
      assert_equal Billing::Money.new(7_00), receipt.plan_amount

      assert_equal Billing::Money.new(7_00), receipt.amount
    end

    test "works with shared storage usage items that only uses free usage without plan" do
      listing = create(:marketplace_listing)
      transaction = create(:billing_transaction,
        plan_name: nil,
        amount_in_cents: 2_50)
      create :billing_transaction_line_item,
        subscribable: create(:marketplace_listing_plan, listing: listing),
        listing: listing,
        amount_in_cents: 2_50,
        billing_transaction: transaction
      create :billing_transaction_line_item,
        :shared_storage,
        quantity: 380_928, # 0.5GB of usage
        amount_in_cents: 0,
        billing_transaction: transaction

      exception = RuntimeError.new("Missing plan_name in billing transaction with shared storage usage")
      Failbot.stubs(:report)
      Failbot.expects(:report).with(exception, { "gh.billing.transaction.id" => transaction.id })

      receipt = Billing::Receipt.new(transaction)

      shared_storage_text = T.must(receipt.shared_storage_line_items_text).split("\n")

      # No plan to calculate total minutes - shows as included.
      assert_equal "0.5GB included storage $0.00 USD", shared_storage_text[0]

      assert_equal Billing::Money.new(0), receipt.shared_storage_amount
      assert_equal Billing::Money.new(2_50), receipt.marketplace_amount
      assert_equal Billing::Money.new(2_50), receipt.amount
    end

    test "works with shared storage usage overages" do
      transaction = create(:billing_transaction,
        amount_in_cents: 9_75)
      listing = create(:marketplace_listing)
      create :billing_transaction_line_item,
        subscribable: create(:marketplace_listing_plan, listing: listing),
        listing: listing,
        amount_in_cents: 2_50,
        billing_transaction: transaction

      create :billing_transaction_line_item,
        :shared_storage,
        quantity: 761_856, # 1GB of usage
        amount_in_cents: 0,
        billing_transaction: transaction

      create :billing_transaction_line_item,
        :shared_storage,
        quantity: 761_856, # 1GB of usage
        amount_in_cents: 25,
        billing_transaction: transaction

      receipt = Billing::Receipt.new(transaction)

      shared_storage_text = T.must(receipt.shared_storage_line_items_text).split("\n")

      assert_includes(shared_storage_text, "1.0GB included storage $0.00 USD")
      assert_includes(shared_storage_text, "1.0GB additional storage $0.25 USD")

      assert_equal Billing::Money.new(25), receipt.shared_storage_amount
      assert_equal Billing::Money.new(2_50), receipt.marketplace_amount

      # 9_75 (transaction amount) - 25 (shared_storage_amount) - 2_50 (marketplace_amount)
      assert_equal Billing::Money.new(7_00), receipt.plan_amount

      assert_equal Billing::Money.new(9_75), receipt.amount
    end

    test "does not display shared storage usage items when quantity and cost are zero" do
      transaction = create(:billing_transaction,
        amount_in_cents: 9_75)
      listing = create(:marketplace_listing)
      create :billing_transaction_line_item,
        subscribable: create(:marketplace_listing_plan, listing: listing),
        listing: listing,
        amount_in_cents: 2_50,
        billing_transaction: transaction

      create :billing_transaction_line_item,
        :shared_storage,
        quantity: 761_856, # 1GB of usage
        amount_in_cents: 25,
        billing_transaction: transaction

      create :billing_transaction_line_item,
        :shared_storage,
        quantity: 0,
        amount_in_cents: 0,
        billing_transaction: transaction

      receipt = Billing::Receipt.new(transaction)
      receipt.billable_entity.enable_feature(:filter_zero_value_line_items)

      shared_storage_text = T.must(receipt.shared_storage_line_items_text).split("\n")

      assert_equal 1, shared_storage_text.size
      assert_includes(shared_storage_text, "1.0GB additional storage $0.25 USD")

      assert_equal Billing::Money.new(25), receipt.shared_storage_amount
      assert_equal Billing::Money.new(2_50), receipt.marketplace_amount
      assert_equal Billing::Money.new(7_00), receipt.plan_amount
      assert_equal Billing::Money.new(9_75), receipt.amount
    end

    test "does not display codespaces usage items that only uses included usage without plan" do
      listing = create(:marketplace_listing)
      transaction = create(:billing_transaction,
        plan_name: nil,
        amount_in_cents: 2_50)
      create :billing_transaction_line_item,
        subscribable: create(:marketplace_listing_plan, listing: listing),
        listing: listing,
        amount_in_cents: 2_50,
        billing_transaction: transaction
      create :billing_transaction_line_item,
        :codespaces_storage_usage,
        quantity: 160,
        amount_in_cents: 0,
        billing_transaction: transaction
      create :billing_transaction_line_item,
        :codespaces_compute_d2_usage,
        quantity: 10,
        amount_in_cents: 0,
        billing_transaction: transaction

      exception = RuntimeError.new("Missing plan_name in billing transaction with codespaces usage")
      Failbot.stubs(:report)
      Failbot.expects(:report).with(exception, { "gh.billing.transaction.id" => transaction.id })

      receipt = Billing::Receipt.new(transaction)

      assert_equal "", receipt.codespaces_line_items_text

      assert_equal Billing::Money.new(0), receipt.codespaces_amount
      assert_equal Billing::Money.new(2_50), receipt.marketplace_amount
      assert_equal Billing::Money.new(2_50), receipt.amount
    end

    test "does not display codespaces usage items that only uses included usage with plan" do
      listing = create(:marketplace_listing)
      transaction = create(:billing_transaction,
        amount_in_cents: 2_50,
        plan_name: "pro")
      create :billing_transaction_line_item,
        subscribable: create(:marketplace_listing_plan, listing: listing),
        listing: listing,
        amount_in_cents: 2_50,
        billing_transaction: transaction
      create :billing_transaction_line_item,
        :codespaces_storage_usage,
        quantity: 160,
        amount_in_cents: 0,
        billing_transaction: transaction
      create :billing_transaction_line_item,
        :codespaces_compute_d2_usage,
        quantity: 10,
        amount_in_cents: 0,
        billing_transaction: transaction

      Failbot.stubs(:report)
      Failbot.expects(:report).never

      receipt = Billing::Receipt.new(transaction)

      mock_get_entitlement_plans

      included_usage = "180 core-hours included\n20GB of storage included"
      assert_equal included_usage, receipt.codespaces_line_items_text

      assert_equal Billing::Money.new(0), receipt.codespaces_amount
      assert_equal Billing::Money.new(2_50), receipt.marketplace_amount
      assert_equal Billing::Money.new(2_50), receipt.amount
    end

    test "works with codespaces usage overages" do
      transaction = create(:billing_transaction,
        amount_in_cents: 9_75,
        plan_name: "pro")
      listing = create(:marketplace_listing)
      create :billing_transaction_line_item,
        subscribable: create(:marketplace_listing_plan, listing: listing),
        listing: listing,
        amount_in_cents: 2_50,
        billing_transaction: transaction

      create :billing_transaction_line_item,
        :codespaces_storage_usage,
        quantity: 160,
        amount_in_cents: 0,
        billing_transaction: transaction
      create :billing_transaction_line_item,
        :codespaces_compute_d2_usage,
        quantity: 10,
        amount_in_cents: 0,
        billing_transaction: transaction
      create :billing_transaction_line_item,
        :codespaces_storage_usage,
        quantity: 5,
        amount_in_cents: 20,
        billing_transaction: transaction
      create :billing_transaction_line_item,
        :codespaces_compute_d2_usage,
        quantity: 20,
        amount_in_cents: 10,
        billing_transaction: transaction

      receipt = Billing::Receipt.new(transaction)

      mock_get_entitlement_plans

      codespaces_text = receipt.codespaces_line_items_text.split("\n")
      assert_equal "20 hours of compute (2 core)", codespaces_text[2]
      assert_equal "5GB of storage", codespaces_text[3]

      assert_equal Billing::Money.new(30), receipt.codespaces_amount
      assert_equal Billing::Money.new(2_50), receipt.marketplace_amount

      # 9_75 (transaction amount) - 25 (shared_storage_amount) - 2_50 (marketplace_amount) - 30 (codespaces_amount)
      assert_equal Billing::Money.new(6_95), receipt.plan_amount

      assert_equal Billing::Money.new(9_75), receipt.amount
    end

    test "displays decimal quantity for codespaces line items when it is a decimal value" do
      transaction = create(:billing_transaction,
        amount_in_cents: 10,
        plan_name: GitHub::Plan.pro)

      create :billing_transaction_line_item,
        :codespaces_storage_usage,
        quantity: 160,
        amount_in_cents: 0,
        billing_transaction: transaction
      create :billing_transaction_line_item,
        :codespaces_compute_d2_usage,
        quantity: 10,
        amount_in_cents: 0,
        billing_transaction: transaction
      create :billing_transaction_line_item,
        :codespaces_storage_usage,
        quantity: 123.456,
        amount_in_cents: 20,
        billing_transaction: transaction
      create :billing_transaction_line_item,
        :codespaces_compute_d2_usage,
        quantity: 123.456,
        amount_in_cents: 10,
        billing_transaction: transaction

      receipt = Billing::Receipt.new(transaction)

      mock_get_entitlement_plans

      codespaces_text = receipt.codespaces_line_items_text.split("\n")

      assert_equal "123.456 hours of compute (2 core)", codespaces_text[2]
      assert_equal "123.456GB of storage", codespaces_text[3]

      assert_equal Billing::Money.new(30), receipt.codespaces_amount
    end

    test "does not pluralize codespaces line items with 1 hour of compute" do
      transaction = create(:billing_transaction,
        amount_in_cents: 10,
        plan_name: GitHub::Plan.pro)

      create :billing_transaction_line_item,
        :codespaces_storage_usage,
        quantity: 160,
        amount_in_cents: 0,
        billing_transaction: transaction
      create :billing_transaction_line_item,
        :codespaces_compute_d2_usage,
        quantity: 10,
        amount_in_cents: 0,
        billing_transaction: transaction
      create :billing_transaction_line_item,
        :codespaces_storage_usage,
        quantity: 2,
        amount_in_cents: 20,
        billing_transaction: transaction
      create :billing_transaction_line_item,
        :codespaces_compute_d2_usage,
        quantity: 1,
        amount_in_cents: 10,
        billing_transaction: transaction

      receipt = Billing::Receipt.new(transaction)

      mock_get_entitlement_plans

      codespaces_text = receipt.codespaces_line_items_text.split("\n")
      assert_equal "1 hour of compute (2 core)", codespaces_text[2]
      assert_equal "2GB of storage", codespaces_text[3]

      assert_equal Billing::Money.new(30), receipt.codespaces_amount
    end

    context "codespaces with entitlements" do
      test "does not display codespaces usage items that only uses included usage without plan" do
        ::Codespaces::Policy.expects(:entitlements_feature_enabled?).returns(true)

        listing = create(:marketplace_listing)
        transaction = create(:billing_transaction,
          plan_name: nil,
          amount_in_cents: 2_50)
        create :billing_transaction_line_item,
          subscribable: create(:marketplace_listing_plan, listing: listing),
          listing: listing,
          amount_in_cents: 2_50,
          billing_transaction: transaction
        create :billing_transaction_line_item,
          :codespaces_storage_usage,
          quantity: 160,
          amount_in_cents: 0,
          billing_transaction: transaction
        create :billing_transaction_line_item,
          :codespaces_compute_d2_usage,
          quantity: 10,
          amount_in_cents: 0,
          billing_transaction: transaction

        exception = RuntimeError.new("Missing plan_name in billing transaction with codespaces usage")
        Failbot.stubs(:report)
        Failbot.expects(:report).with(exception, { "gh.billing.transaction.id" => transaction.id })

        receipt = Billing::Receipt.new(transaction)

        assert_equal "", receipt.codespaces_line_items_text

        assert_equal Billing::Money.new(0), receipt.codespaces_amount
        assert_equal Billing::Money.new(2_50), receipt.marketplace_amount
        assert_equal Billing::Money.new(2_50), receipt.amount
      end

      test "Displays codespaces usage item with allotted entitlements with a plan" do
        ::Codespaces::Policy.expects(:entitlements_feature_enabled?).returns(true)
        mock_get_entitlement_plans

        listing = create(:marketplace_listing)
        transaction = create(:billing_transaction,
          amount_in_cents: 2_50,
          plan_name: "pro")
        create :billing_transaction_line_item,
          subscribable: create(:marketplace_listing_plan, listing: listing),
          listing: listing,
          amount_in_cents: 2_50,
          billing_transaction: transaction
        create :billing_transaction_line_item,
          :codespaces_storage_usage,
          quantity: 160,
          amount_in_cents: 0,
          billing_transaction: transaction
        create :billing_transaction_line_item,
          :codespaces_compute_d2_usage,
          quantity: 10,
          amount_in_cents: 0,
          billing_transaction: transaction

        Failbot.stubs(:report)
        Failbot.expects(:report).never

        receipt = Billing::Receipt.new(transaction)

        included_usage = "180 core-hours included\n20GB of storage included"
        assert_equal included_usage, receipt.codespaces_line_items_text

        assert_equal Billing::Money.new(0), receipt.codespaces_amount
        assert_equal Billing::Money.new(2_50), receipt.marketplace_amount
        assert_equal Billing::Money.new(2_50), receipt.amount
      end

      test "works with codespaces usage overages" do
        ::Codespaces::Policy.expects(:entitlements_feature_enabled?).returns(true)
        mock_get_entitlement_plans

        transaction = create(:billing_transaction,
          amount_in_cents: 9_75,
          plan_name: "pro",
          user: create(:credit_card_user)
        )

        mock_codespaces_get_usage_breakdown(billable_owner: transaction.user, entitlements_exhausted: true)

        listing = create(:marketplace_listing)
        create :billing_transaction_line_item,
          subscribable: create(:marketplace_listing_plan, listing: listing),
          listing: listing,
          amount_in_cents: 2_50,
          billing_transaction: transaction

        create :billing_transaction_line_item,
          :codespaces_storage_usage,
          quantity: 160,
          amount_in_cents: 0,
          billing_transaction: transaction
        create :billing_transaction_line_item,
          :codespaces_compute_d2_usage,
          quantity: 10,
          amount_in_cents: 0,
          billing_transaction: transaction
        create :billing_transaction_line_item,
          :codespaces_storage_usage,
          quantity: 5,
          amount_in_cents: 20,
          billing_transaction: transaction
        create :billing_transaction_line_item,
          :codespaces_compute_d2_usage,
          quantity: 20,
          amount_in_cents: 10,
          billing_transaction: transaction

        receipt = Billing::Receipt.new(transaction)
        codespaces_text = receipt.codespaces_line_items_text.split("\n")
        assert_equal "180 core-hours included", codespaces_text[0]
        assert_equal "20GB of storage included", codespaces_text[1]
        assert_equal "20 additional hours of compute (2 core)", codespaces_text[2]
        assert_equal "5GB of additional storage", codespaces_text[3]

        assert_equal Billing::Money.new(30), receipt.codespaces_amount
        assert_equal Billing::Money.new(2_50), receipt.marketplace_amount

        # 9_75 (transaction amount) - 25 (shared_storage_amount) - 2_50 (marketplace_amount) - 30 (codespaces_amount)
        assert_equal Billing::Money.new(6_95), receipt.plan_amount

        assert_equal Billing::Money.new(9_75), receipt.amount
      end

      test "displays decimal quantity for codespaces line items when it is a decimal value" do
        ::Codespaces::Policy.expects(:entitlements_feature_enabled?).returns(true)
        mock_get_entitlement_plans

        transaction = create(:billing_transaction,
          amount_in_cents: 9_75,
          plan_name: "pro",
          user: create(:credit_card_user)
        )

        mock_codespaces_get_usage_breakdown(billable_owner: transaction.user, entitlements_exhausted: true)

        create :billing_transaction_line_item,
          :codespaces_storage_usage,
          quantity: 160,
          amount_in_cents: 0,
          billing_transaction: transaction
        create :billing_transaction_line_item,
          :codespaces_compute_d2_usage,
          quantity: 10,
          amount_in_cents: 0,
          billing_transaction: transaction
        create :billing_transaction_line_item,
          :codespaces_storage_usage,
          quantity: 123.456,
          amount_in_cents: 20,
          billing_transaction: transaction
        create :billing_transaction_line_item,
          :codespaces_compute_d2_usage,
          quantity: 123.456,
          amount_in_cents: 10,
          billing_transaction: transaction

        receipt = Billing::Receipt.new(transaction)

        codespaces_text = receipt.codespaces_line_items_text.split("\n")
        assert_equal "180 core-hours included", codespaces_text[0]
        assert_equal "20GB of storage included", codespaces_text[1]
        assert_equal "123.456 additional hours of compute (2 core)", codespaces_text[2]
        assert_equal "123.456GB of additional storage", codespaces_text[3]

        assert_equal Billing::Money.new(30), receipt.codespaces_amount
      end

      test "does not pluralize codespaces line items with 1 hour of compute" do
        ::Codespaces::Policy.expects(:entitlements_feature_enabled?).returns(true)
        mock_get_entitlement_plans

        transaction = create(:billing_transaction,
          amount_in_cents: 9_75,
          plan_name: "pro",
          user: create(:credit_card_user)
        )

        mock_codespaces_get_usage_breakdown(billable_owner: transaction.user, entitlements_exhausted: true)

        create :billing_transaction_line_item,
          :codespaces_storage_usage,
          quantity: 160,
          amount_in_cents: 0,
          billing_transaction: transaction
        create :billing_transaction_line_item,
          :codespaces_compute_d2_usage,
          quantity: 10,
          amount_in_cents: 0,
          billing_transaction: transaction
        create :billing_transaction_line_item,
          :codespaces_storage_usage,
          quantity: 2,
          amount_in_cents: 20,
          billing_transaction: transaction
        create :billing_transaction_line_item,
          :codespaces_compute_d2_usage,
          quantity: 1,
          amount_in_cents: 10,
          billing_transaction: transaction

        receipt = Billing::Receipt.new(transaction)

        codespaces_text = receipt.codespaces_line_items_text.split("\n")
        assert_equal "180 core-hours included", codespaces_text[0]
        assert_equal "20GB of storage included", codespaces_text[1]
        assert_equal "1 additional hour of compute (2 core)", codespaces_text[2]
        assert_equal "2GB of additional storage", codespaces_text[3]

        assert_equal Billing::Money.new(30), receipt.codespaces_amount
      end

      test "displays without entitlements if we fail to fetch entitlements" do
        ::Codespaces::Policy.expects(:entitlements_feature_enabled?).returns(true)
        stub_get_entitlement_plans_client_error

        transaction = create(:billing_transaction,
          amount_in_cents: 9_75,
          plan_name: "pro",
          user: create(:credit_card_user)
        )

        mock_codespaces_get_usage_breakdown(billable_owner: transaction.user, entitlements_exhausted: true)

        create :billing_transaction_line_item,
          :codespaces_storage_usage,
          quantity: 160,
          amount_in_cents: 0,
          billing_transaction: transaction
        create :billing_transaction_line_item,
          :codespaces_compute_d2_usage,
          quantity: 10,
          amount_in_cents: 0,
          billing_transaction: transaction
        create :billing_transaction_line_item,
          :codespaces_storage_usage,
          quantity: 123.456,
          amount_in_cents: 20,
          billing_transaction: transaction
        create :billing_transaction_line_item,
          :codespaces_compute_d2_usage,
          quantity: 123.456,
          amount_in_cents: 10,
          billing_transaction: transaction

        receipt = Billing::Receipt.new(transaction)
        codespaces_text = receipt.codespaces_line_items_text.split("\n")

        refute receipt.codespaces_line_items_text.include?("included")
        assert_equal "123.456 additional hours of compute (2 core)", codespaces_text[0]
        assert_equal "123.456GB of additional storage", codespaces_text[1]
        refute codespaces_text[2]

        assert_equal Billing::Money.new(30), receipt.codespaces_amount
      end

      test "displays without 'additional' language if we fail to fetch usage breakdown info" do
        ::Codespaces::Policy.expects(:entitlements_feature_enabled?).returns(true)
        mock_get_entitlement_plans
        mock_get_usage_breakdown_response_error

        transaction = create(:billing_transaction,
          amount_in_cents: 9_75,
          plan_name: "pro",
          user: create(:credit_card_user)
        )

        create :billing_transaction_line_item,
          :codespaces_storage_usage,
          quantity: 160,
          amount_in_cents: 0,
          billing_transaction: transaction
        create :billing_transaction_line_item,
          :codespaces_compute_d2_usage,
          quantity: 10,
          amount_in_cents: 0,
          billing_transaction: transaction
        create :billing_transaction_line_item,
          :codespaces_storage_usage,
          quantity: 123.456,
          amount_in_cents: 20,
          billing_transaction: transaction
        create :billing_transaction_line_item,
          :codespaces_compute_d2_usage,
          quantity: 123.456,
          amount_in_cents: 10,
          billing_transaction: transaction

        receipt = Billing::Receipt.new(transaction)
        codespaces_text = receipt.codespaces_line_items_text.split("\n")

        refute receipt.codespaces_line_items_text.include?("additional")
        assert_equal "180 core-hours included", codespaces_text[0]
        assert_equal "20GB of storage included", codespaces_text[1]
        assert_equal "123.456 hours of compute (2 core)", codespaces_text[2]
        assert_equal "123.456GB of storage", codespaces_text[3]

        assert_equal Billing::Money.new(30), receipt.codespaces_amount
      end
    end

    test "works with Copilot Business usage overages" do
      transaction = create(:billing_transaction,
        amount_in_cents: 9_75,
        plan_name: "pro")

      create :billing_transaction_line_item,
        :copilot_for_business_usage,
        quantity: 1,
        amount_in_cents: 19_00,
        billing_transaction: transaction,
        extras: { "seats_billed_in_full" => 18, "unit_price" => 19, "prorations" => [{ "days" => 15, "count" => 2 }] }

      receipt = Billing::Receipt.new(transaction)

      copilot_for_business_breakdown_text = receipt.metered_copilot_text.split("\n")
      assert_includes(copilot_for_business_breakdown_text, "1 total billed seat")
      assert_includes(copilot_for_business_breakdown_text, "18 seats ($19/month each)")
      assert_includes(copilot_for_business_breakdown_text, "2 seats ($19/month each - prorated for 15 days)")

      assert_equal Billing::Money.new(19_00), receipt.copilot_for_business_amount
      assert_equal Billing::Money.new(0), receipt.plan_amount
      assert_equal Billing::Money.new(9_75), receipt.amount
    end

    test "rounds Copilot Business usage quantity to 4 decimal places" do
      transaction = create(:billing_transaction,
        amount_in_cents: 9_75,
        plan_name: "pro")

      create :billing_transaction_line_item,
        :copilot_for_business_usage,
        quantity: 1.234567890,
        amount_in_cents: 23_46, # 1.234567890 users * $19.00/user
        billing_transaction: transaction,
        extras: { "unit_price" => 19 , "prorations" => [{ "days" => 15, "count" => 3 }] }

      receipt = Billing::Receipt.new(transaction)
      copilot_for_business_text = receipt.metered_copilot_text.split("\n")
      assert_includes(copilot_for_business_text, "Business:")
      assert_includes(copilot_for_business_text, "3 seats ($19/month each - prorated for 15 days)")
      assert_includes(copilot_for_business_text, "1.2346 total billed seats")
    end

    test "does not display Copilot Business usage overages with 0 amount" do
      transaction = create(:billing_transaction,
        amount_in_cents: 9_75,
        plan_name: "pro")

      create :billing_transaction_line_item,
        :copilot_for_business_usage,
        quantity: 0,
        amount_in_cents: 0,
        billing_transaction: transaction

      receipt = Billing::Receipt.new(transaction)

      copilot_for_business_breakdown_text = receipt.metered_copilot_text.split("\n")
      assert_includes(copilot_for_business_breakdown_text, "0 total billed seats")

      assert_equal Billing::Money.new(0), receipt.copilot_for_business_amount
    end

    test "works with Copilot Enterprise usage" do
      create :billing_product_uuid, :copilot_enterprise

      transaction = create(:billing_transaction,
        amount_in_cents: 9_75,
        plan_name: "enterprise")

      create :billing_transaction_line_item,
        :copilot_enterprise_usage,
        quantity: 1,
        amount_in_cents: 39_00,
        billing_transaction: transaction

      receipt = Billing::Receipt.new(transaction)

      copilot_enterprise_text = receipt.metered_copilot_text.split("\n")
      assert_includes(copilot_enterprise_text, "1 billed seat ($39/month each)")
      assert_includes(copilot_enterprise_text, "Enterprise:")
      assert_equal Billing::Money.new(39_00), receipt.metered_copilot_amount
    end

    test "works with Copilot standalone usage" do
      create :billing_product_uuid, :copilot_standalone

      transaction = create(:billing_transaction,
        amount_in_cents: 9_75,
        plan_name: "business")

      create :billing_transaction_line_item,
        :copilot_standalone_usage,
        quantity: 1,
        amount_in_cents: 19_00,
        billing_transaction: transaction

      receipt = Billing::Receipt.new(transaction)

      copilot_standalone_text = receipt.metered_copilot_text.split("\n")
      assert_includes(copilot_standalone_text, "1 billed seat ($19/month each)")
      assert_includes(copilot_standalone_text, "Business:")
      assert_equal Billing::Money.new(19_00), receipt.metered_copilot_amount
    end

    test "works with multiple metered Copilot skus" do
      create :billing_product_uuid, :copilot_enterprise
      transaction = create(:billing_transaction,
        amount_in_cents: 9_75,
        plan_name: "enterprise")

      create :billing_transaction_line_item,
        :copilot_for_business_usage,
        quantity: 1,
        amount_in_cents: 19_00,
        billing_transaction: transaction,
        extras: { "unit_price" => 19, "prorations" => [{ "days" => 15, "count" => 2 }] }

      create :billing_transaction_line_item,
        :copilot_enterprise_usage,
        quantity: 1,
        amount_in_cents: 39_00,
        billing_transaction: transaction

      receipt = Billing::Receipt.new(transaction)

      copilot_text = receipt.metered_copilot_text.split("\n")
      assert_includes(copilot_text, "2 seats ($19/month each - prorated for 15 days)")
      assert_includes(copilot_text, "1 billed seat ($39/month each)")
      assert_equal Billing::Money.new(58_00), receipt.metered_copilot_amount
    end

    test "works with multiple metered Copilot skus summed" do
      create :billing_product_uuid, :copilot_enterprise
      transaction = create(:billing_transaction,
        amount_in_cents: 9_75,
        plan_name: "enterprise")

      create :billing_transaction_line_item,
        :copilot_for_business_usage,
        quantity: 1,
        amount_in_cents: 19_00,
        billing_transaction: transaction,
        extras: { "unit_price" => 19, "prorations" => [{ "days" => 14, "count" => 2 }], "seats_billed_in_full" => 2 }

      create :billing_transaction_line_item,
        :copilot_enterprise_usage,
        quantity: 1,
        amount_in_cents: 39_00,
        billing_transaction: transaction
      create :billing_transaction_line_item,
        :copilot_enterprise_usage,
        quantity: 4,
        amount_in_cents: 39_00,
        billing_transaction: transaction

      receipt = Billing::Receipt.new(transaction)

      copilot_text = receipt.metered_copilot_text.split("\n")
      assert_includes(copilot_text, "2 seats ($19/month each)")
      assert_includes(copilot_text, "2 seats ($19/month each - prorated for 14 days)")
      assert_includes(copilot_text, "5 billed seats ($39/month each)")
    end

    test "always includes total billed line per sku" do
      create :billing_product_uuid, :copilot_enterprise
      transaction = create(:billing_transaction,
        amount_in_cents: 9_75,
        plan_name: "enterprise")

      create :billing_transaction_line_item,
        :copilot_for_business_usage,
        quantity: 2.6,
        amount_in_cents: 19_00,
        billing_transaction: transaction,
        extras: { "unit_price" => "19.0", "prorations" => [{ "days" => 14, "count" => 2 }], "seats_billed_in_full" => 2 }

      create :billing_transaction_line_item,
        :copilot_for_business_usage,
        quantity: 2,
        amount_in_cents: 19_00,
        billing_transaction: transaction,
        extras: { "unit_price" => "19.0", "prorations" => [{ "days" => 14, "count" => 2 }], "seats_billed_in_full" => 2 }

      create :billing_transaction_line_item,
        :copilot_enterprise_usage,
        quantity: 1,
        amount_in_cents: 39_00,
        billing_transaction: transaction
      create :billing_transaction_line_item,
        :copilot_enterprise_usage,
        quantity: 4,
        amount_in_cents: 39_00,
        billing_transaction: transaction

      receipt = Billing::Receipt.new(transaction)

      copilot_text = receipt.metered_copilot_text.split("\n")
      assert_includes(copilot_text, "4.6 billed seats ($19/month each)")
      assert_includes(copilot_text, "5 billed seats ($39/month each)")
    end
  end

  context "filter zero value line items feature flag" do
    test "zero value items not filtered when feature flag disabled" do

      transaction = create(:billing_transaction,
        amount_in_cents: 9_75)
      create :billing_transaction_line_item,
        :actions_16_core,
        quantity: 0,
        amount_in_cents: 0,
        billing_transaction: transaction

      receipt = Billing::Receipt.new(transaction)
      receipt.billable_entity.disable_feature(:filter_zero_value_line_items)

      assert_equal 1, receipt.filter_zero_value_line_items(receipt.actions_line_items).count
    end

    test "zero value items filtered when feature flag enabled" do

      transaction = create(:billing_transaction,
        amount_in_cents: 9_75)
      create :billing_transaction_line_item,
        :actions_16_core,
        quantity: 0,
        amount_in_cents: 0,
        billing_transaction: transaction

      receipt = Billing::Receipt.new(transaction)
      receipt.billable_entity.enable_feature(:filter_zero_value_line_items)

      assert_equal 0, receipt.filter_zero_value_line_items(receipt.actions_line_items).count
    end

    test "zero value items filtered when feature flag enabled globally and user no longer exists" do

      transaction = create(
        :billing_transaction,
        amount_in_cents: 9_75,
      )

      # Make a DeadUser
      transaction.user = nil
      transaction.save!

      create :billing_transaction_line_item,
        :actions_16_core,
        quantity: 0,
        amount_in_cents: 0,
        billing_transaction: transaction

      receipt = Billing::Receipt.new(transaction)
      GitHub.flipper[:filter_zero_value_line_items].enable

      assert_equal 0, receipt.filter_zero_value_line_items(receipt.actions_line_items).count
    end

    test "zero value items not filtered when feature flag disabled globally and user no longer exists" do

      transaction = create(
        :billing_transaction,
        amount_in_cents: 9_75,
      )

      # Make a DeadUser
      transaction.user = nil
      transaction.save!

      create :billing_transaction_line_item,
        :actions_16_core,
        quantity: 0,
        amount_in_cents: 0,
        billing_transaction: transaction

      receipt = Billing::Receipt.new(transaction)
      GitHub.flipper[:filter_zero_value_line_items].disable

      assert_equal 1, receipt.filter_zero_value_line_items(receipt.actions_line_items).count
    end
  end

  context "use generic line item format" do
    test "generic line item feature enabled for viewer when created after effective date and feature flag enabled" do

      transaction = create(
        :billing_transaction,
        amount_in_cents: 9_75,
        created_at: Billing::Receipt::LINE_ITEM_PRODUCT_RATE_PLAN_CHARGE_IDS_EFFECTIVE_DATE
      )
      create :billing_transaction_line_item,
        :actions_16_core,
        quantity: 0,
        amount_in_cents: 0,
        billing_transaction: transaction

      @user.enable_feature(:payment_receipt_line_item_format)
      receipt = Billing::Receipt.new(transaction, viewer: @user)

      assert receipt.generic_line_item_feature_enabled_for_viewer?
    end

    test "generic line item feature disabled for viewer when created after effective date and feature flag disabled" do

      transaction = create(
        :billing_transaction,
        amount_in_cents: 9_75,
        created_at: Billing::Receipt::LINE_ITEM_PRODUCT_RATE_PLAN_CHARGE_IDS_EFFECTIVE_DATE
      )
      create :billing_transaction_line_item,
        :actions_16_core,
        quantity: 0,
        amount_in_cents: 0,
        billing_transaction: transaction

      @user.disable_feature(:payment_receipt_line_item_format)
      receipt = Billing::Receipt.new(transaction, viewer: @user)

      assert !receipt.generic_line_item_feature_enabled_for_viewer?
    end

    test "generic line item feature disabled for viewer when created before effective date and feature flag enabled" do

      transaction = create(
        :billing_transaction,
        amount_in_cents: 9_75,
        created_at: Billing::Receipt::LINE_ITEM_PRODUCT_RATE_PLAN_CHARGE_IDS_EFFECTIVE_DATE - 1.day
      )
      create :billing_transaction_line_item,
        :actions_16_core,
        quantity: 0,
        amount_in_cents: 0,
        billing_transaction: transaction

      @user.enable_feature(:payment_receipt_line_item_format)
      receipt = Billing::Receipt.new(transaction, viewer: @user)

      assert !receipt.generic_line_item_feature_enabled_for_viewer?
    end

    test "generic line item feature enabled for billable entity when created after effective date and feature flag enabled" do

      transaction = create(
        :billing_transaction,
        amount_in_cents: 9_75,
        created_at: Billing::Receipt::LINE_ITEM_PRODUCT_RATE_PLAN_CHARGE_IDS_EFFECTIVE_DATE
      )
      create :billing_transaction_line_item,
        :actions_16_core,
        quantity: 0,
        amount_in_cents: 0,
        billing_transaction: transaction

      receipt = Billing::Receipt.new(transaction)
      receipt.billable_entity.enable_feature(:payment_receipt_line_item_format)

      assert receipt.generic_line_item_feature_enabled_for_billable_entity?
    end

    test "generic line item feature disabled for billable entity when created after effective date and feature flag disabled" do

      transaction = create(
        :billing_transaction,
        amount_in_cents: 9_75,
        created_at: Billing::Receipt::LINE_ITEM_PRODUCT_RATE_PLAN_CHARGE_IDS_EFFECTIVE_DATE
      )
      create :billing_transaction_line_item,
        :actions_16_core,
        quantity: 0,
        amount_in_cents: 0,
        billing_transaction: transaction

      receipt = Billing::Receipt.new(transaction)
      receipt.billable_entity.disable_feature(:payment_receipt_line_item_format)

      assert !receipt.generic_line_item_feature_enabled_for_billable_entity?
    end

    test "generic line item feature disabled for billable entity when created before effective date and feature flag enabled" do

      transaction = create(
        :billing_transaction,
        amount_in_cents: 9_75,
        created_at: Billing::Receipt::LINE_ITEM_PRODUCT_RATE_PLAN_CHARGE_IDS_EFFECTIVE_DATE - 1.day
      )
      create :billing_transaction_line_item,
        :actions_16_core,
        quantity: 0,
        amount_in_cents: 0,
        billing_transaction: transaction

      receipt = Billing::Receipt.new(transaction)
      receipt.billable_entity.enable_feature(:payment_receipt_line_item_format)

      assert !receipt.generic_line_item_feature_enabled_for_billable_entity?
    end

    test "generic line item feature enabled when user no longer exists and feature flag enabled globally" do

      transaction = create(
        :billing_transaction,
        amount_in_cents: 9_75,
        created_at: Billing::Receipt::LINE_ITEM_PRODUCT_RATE_PLAN_CHARGE_IDS_EFFECTIVE_DATE
      )

      # Make a DeadUser
      transaction.user = nil
      transaction.save!

      create :billing_transaction_line_item,
        :actions_16_core,
        quantity: 0,
        amount_in_cents: 0,
        billing_transaction: transaction

      receipt = Billing::Receipt.new(transaction)
      GitHub.flipper[:payment_receipt_line_item_format].enable

      assert receipt.generic_line_item_feature_enabled_for_billable_entity?
    end


    test "generic line item feature disabled when user no longer exists and feature flag disabled globally" do

      transaction = create(
        :billing_transaction,
        amount_in_cents: 9_75,
        created_at: Billing::Receipt::LINE_ITEM_PRODUCT_RATE_PLAN_CHARGE_IDS_EFFECTIVE_DATE
      )

      # Make a DeadUser
      transaction.user = nil
      transaction.save!

      create :billing_transaction_line_item,
        :actions_16_core,
        quantity: 0,
        amount_in_cents: 0,
        billing_transaction: transaction

      receipt = Billing::Receipt.new(transaction)
      GitHub.flipper[:payment_receipt_line_item_format].disable

      assert !receipt.generic_line_item_feature_enabled_for_billable_entity?
    end

    test "generic line item format groups GitHub Team Plan Monthly and Annual line items" do

      service_start_date = Time.now.to_date
      service_end_date_month = (service_start_date + 1.month).to_date
      service_end_date_year = (service_start_date + 1.year).to_date

      plan_monthly_product_uuid = create(
        :billing_product_uuid,
        product_type: "github.plan",
        product_key: "business",
        billing_cycle: "month",
        zuora_product_rate_plan_charge_ids: { unit: "1", base_unit: "2" },
      )

      plan_yearly_product_uuid = create(
        :billing_product_uuid,
        product_type: "github.plan",
        product_key: "business",
        billing_cycle: "year",
        zuora_product_rate_plan_charge_ids: { unit: "3", base_unit: "4" },
      )

      github_team_monthly_rate_plan_charge_ids = plan_monthly_product_uuid.zuora_product_rate_plan_charge_ids
      github_team_annual_rate_plan_charge_ids = plan_yearly_product_uuid.zuora_product_rate_plan_charge_ids

      transaction = create(
        :billing_transaction,
        amount_in_cents: 9_75,
      )

      create :billing_transaction_line_item,
        description: "GitHub Team Plan - Monthly",
        quantity: 1,
        amount_in_cents: 1000,
        zuora_product_rate_plan_charge_id: github_team_monthly_rate_plan_charge_ids[:unit],
        subscribable: nil,
        billing_transaction: transaction,
        service_start_date: service_start_date,
        service_end_date: service_end_date_month

      create :billing_transaction_line_item,
        description: "GitHub Team Plan - Monthly",
        quantity: 2,
        amount_in_cents: 2000,
        zuora_product_rate_plan_charge_id: github_team_monthly_rate_plan_charge_ids[:base_unit],
        subscribable: nil,
        billing_transaction: transaction,
        service_start_date: service_start_date,
        service_end_date: service_end_date_month

      create :billing_transaction_line_item,
        description: "GitHub Team Plan - Annual",
        quantity: 3,
        amount_in_cents: 3000,
        zuora_product_rate_plan_charge_id: github_team_annual_rate_plan_charge_ids[:unit],
        subscribable: nil,
        billing_transaction: transaction,
        service_start_date: service_start_date,
        service_end_date: service_end_date_year

      create :billing_transaction_line_item,
        description: "GitHub Team Plan - Annual",
        quantity: 4,
        amount_in_cents: 4000,
        zuora_product_rate_plan_charge_id: github_team_annual_rate_plan_charge_ids[:base_unit],
        subscribable: nil,
        billing_transaction: transaction,
        service_start_date: service_start_date,
        service_end_date: service_end_date_year

      receipt = Billing::Receipt.new(transaction)
      receipt.billable_entity.enable_feature(:payment_receipt_line_item_format)

      generic_line_items = receipt.generic_line_items
      monthly_line_item = generic_line_items.find { |item| item[:description] == "GitHub Team Plan - Monthly" }
      annual_line_item = generic_line_items.find { |item| item[:description] == "GitHub Team Plan - Annual" }

      assert generic_line_items.count == 2

      assert monthly_line_item&.amount_in_cents == 3000
      assert monthly_line_item&.quantity == 3
      assert monthly_line_item&.service_start_date == service_start_date
      assert monthly_line_item&.service_end_date == service_end_date_month

      assert annual_line_item&.amount_in_cents == 7000
      assert annual_line_item&.quantity == 7
      assert annual_line_item&.service_start_date == service_start_date
      assert annual_line_item&.service_end_date == service_end_date_year
    end
  end
end
