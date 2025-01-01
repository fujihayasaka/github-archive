# typed: true
# frozen_string_literal: true

require "test_helper"
require "pdf-reader"

class Billing::Receipt::PdfRendererTest < GitHub::BillingTestCase
  include CheckAnnotation::ActionsDependency
  include Actions::WorkflowRun::NewsiesAdapter

  fixtures do
    @user = create :credit_card_user,
      login: "dude",
      billing_type: "card",
      plan: GitHub::Plan.find("small"),
      email: "dude@gmail.com",
      billing_extra: "extra billing info"

    @user.customer.update_attribute(:vat_code, "IT12345678901")

    @org = create :credit_card_org,
      login: "coolorg",
      billing_type: "card",
      plan: GitHub::Plan.business,
      seats: 20,
      email: "coolorg@gmail.com"

    @org_with_annual_discount = create :credit_card_org,
      login: "annual-discount-org",
      billing_type: "card",
      plan: GitHub::Plan.business,
      seats: 20,
      email: "my_annual_discount_org@gmail.com",
      plan_duration: "year"

    @now = DateTime.new(2014, 1, 1, 13, 45, 0, "-0800").freeze

    @billing_transaction = create :billing_transaction, user: @user,
                plan_name: "small",
                transaction_id: "bd2gx6",
                amount_in_cents: 12_00,
                plan_price_in_cents: 12_00,
                service_ends_at: @now + 1.month,
                created_at: @now,
                updated_at: @now

    @per_seat_billing_transaction = create :billing_transaction,
                user: @org,
                plan_name: "business",
                transaction_id: "wow555",
                seats_total: 20,
                amount_in_cents: 400_00,
                plan_price_in_cents: 20_00,
                paypal_email: "coolorg-paypal@gmail.com",
                service_ends_at: @now + 1.month,
                created_at: @now,
                updated_at: @now

    @post_munich_now = GitHub::Billing.timezone.parse("2020-04-14").freeze
    @per_seat_billing_transaction_post_munich = create :billing_transaction,
                user: @org,
                plan_name: "business",
                transaction_id: "wow556",
                seats_total: 20,
                amount_in_cents: 400_00,
                plan_price_in_cents: 20_00,
                paypal_email: "coolorg-paypal@gmail.com",
                service_ends_at: @post_munich_now + 1.month,
                created_at: @post_munich_now,
                updated_at: @post_munich_now

    @per_seat_billing_transaction_post_munich_with_discount = create :billing_transaction,
      user: @org,
      plan_name: "business",
      transaction_id: "discount01",
      seats_total: 20,
      amount_in_cents: 760_00,
      plan_price_in_cents: 48_00,
      paypal_email: "discount01@gmail.com",
      renewal_frequency: :yearly,
      service_ends_at: @post_munich_now + 1.year,
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
    @business = @business_billing_transaction.billable_entity

    @credit_balance_transaction = create :billing_transaction, :credit_balance_adjustment, user: @user
  end

  def pdf_for_user
    Billing::Receipt::PdfRenderer.new(Billing::Receipt.new(@billing_transaction))
  end

  def pdf_for_org
    Billing::Receipt::PdfRenderer.new(Billing::Receipt.new(@per_seat_billing_transaction))
  end

  def pdf_for_org_post_munich
    Billing::Receipt::PdfRenderer.new(Billing::Receipt.new(@per_seat_billing_transaction_post_munich))
  end

  def pdf_for_org_post_munich_with_discount
    Billing::Receipt::PdfRenderer.new(Billing::Receipt.new(@per_seat_billing_transaction_post_munich_with_discount))
  end

  def pdf_for_business
    Billing::Receipt::PdfRenderer.new(Billing::Receipt.new(@business_billing_transaction))
  end

  def pdf_for_credit_balance_txn
    Billing::Receipt::PdfRenderer.new(Billing::Receipt.new(@credit_balance_transaction))
  end

  def custom_pdf(billing_transaction)
    Billing::Receipt::PdfRenderer.new(Billing::Receipt.new(billing_transaction))
  end

  def text_of(receipt)
    T.must(PDF::Reader.new(StringIO.new(receipt.render)).pages.first).text
  end

  test "contains the account billed" do
    assert_match "dude", text_of(pdf_for_user)
    assert_match @business.slug, text_of(pdf_for_business)
  end

  test "contains the contact URL" do
    assert_match "Questions? Visit https://support.github.com/contact", text_of(pdf_for_user)
  end

  test "does not contain the support email" do
    refute_match "support@github.com", text_of(pdf_for_user)
  end

  test "contains the Braintree transaction id" do
    assert_match (/bd2gx6/i), text_of(pdf_for_user)
    assert_match (/wow555/i), text_of(pdf_for_org)
    assert_match (/wow779/i), text_of(pdf_for_business)
  end

  test "contains the amount charged" do
    assert_match "$12.00 USD", text_of(pdf_for_user)
    assert_match "$400.00 USD", text_of(pdf_for_org)
    assert_match "$400.00 USD", text_of(pdf_for_business)
  end

  test "contains the date and time of the payment" do
    assert_match "2014-01-01 01:45PM PST", text_of(pdf_for_user)
  end

  test "contains payment method" do
    assert_match "Visa", text_of(pdf_for_user)
    assert_match "4*** **** **** 1234", text_of(pdf_for_user)
    assert_match "PayPal", text_of(pdf_for_org)
    assert_match "coolorg-paypal@gmail.com", text_of(pdf_for_org)
    assert_match "Visa", text_of(pdf_for_business)
    assert_match "4*** **** **** 1234", text_of(pdf_for_business)
  end

  test "does not contain payment method for credit balance transaction" do
    refute_match "Charged to", text_of(pdf_for_credit_balance_txn)
    refute_match "Visa", text_of(pdf_for_credit_balance_txn)
    refute_match "4*** **** **** 1234", text_of(pdf_for_credit_balance_txn)
  end

  test "contains extra billing info" do
    assert_match "extra billing info", text_of(pdf_for_user)
  end

  test "contains vat code" do
    assert_match "IT12345678901", text_of(pdf_for_user)
  end

  test "contains extra billing info with non-latin characters" do
    # Regression test for https://github.com/github/github/issues/10836
    @user.update billing_extra: "余分な課金情報"
    assert_match "余分な課金情報", text_of(pdf_for_user)
  end

  test "contains plan name" do
    assert_match "Small", text_of(pdf_for_user)
  end

  test "contains seats for organization" do
    assert_match "15 additional seats", text_of(pdf_for_org)
    assert_match "Team: 20 seats", text_of(pdf_for_org_post_munich)
  end

  test "contains seats for Business" do
    assert_match "20 seats", text_of(pdf_for_business)
  end

  test "contains the Tax amount for the transaction" do
    billing_transaction = create(:billing_transaction, :with_taxed_line_items, user: @user)
    tax_amount = billing_transaction.tax_amount

    pdf_text = text_of(custom_pdf(billing_transaction))
    assert_match "Tax", pdf_text
    assert_match tax_amount.format(with_currency: true), pdf_text
  end

  test "contains per seat plan annual discount for organization" do
    Organization.any_instance.stubs(:annual_discount_allowed?).returns(true)
    assert_match "Plan Discount               8.33%\n\n\nTotal", text_of(pdf_for_org_post_munich_with_discount)
  end

  test "contains per seat annual discount for a transaction without additional_seats but with seats_delta" do
    Organization.any_instance.stubs(:annual_discount_allowed?).returns(true)
    billing_transaction = create(:billing_transaction,
      user: @org,
      plan_name: "business",
      transaction_id: "discount02",
      seats_delta: 1,
      seats_total: 1,
      amount_in_cents: 44_00,
      plan_price_in_cents: 48_00,
      paypal_email: "discount01@gmail.com",
      renewal_frequency: :yearly,
      transaction_type: "prorate-seat-charge",
      prorated_days: 365,
      service_ends_at: @post_munich_now + 1.year,
      created_at: @post_munich_now,
      updated_at: @post_munich_now
    )

    assert_match /Plan Discount\s*8.33%\n\n\nTotal/, text_of(custom_pdf(billing_transaction))
  end

  test "contains per seat annual discount for an Enterprise transaction without seats_delta but with seats_total" do
    Organization.any_instance.stubs(:annual_discount_allowed?).returns(true)
    billing_transaction = create(:billing_transaction,
      user: @org,
      plan_name: "business_plus",
      transaction_id: "discount02",
      seats_delta: 0,
      seats_total: 1,
      amount_in_cents: 231_00,
      plan_price_in_cents: 252_00,
      paypal_email: "discount01@gmail.com",
      renewal_frequency: :yearly,
      transaction_type: "prorate-seat-charge",
      prorated_days: 365,
      service_ends_at: @post_munich_now + 1.year,
      created_at: @post_munich_now,
      updated_at: @post_munich_now
    )

    assert_match /Plan Discount\s*8.33%\n\n\nTotal/, text_of(custom_pdf(billing_transaction))
  end

  test "contains plan name from transaction if it exists" do
    old_plan = @user.plan
    @billing_transaction.plan_name = "medium"
    @user.update plan: GitHub::Plan.find("medium")
    @user.track_plan_change(@user, old_plan, billing_transaction: @billing_transaction)
    assert_match "Medium", text_of(pdf_for_user)
  end

  test "contains extra billing info for extended latin characters" do
    @user.update billing_extra: "Company: Marcin Mincer spółka cywilna"
    assert_match (/Company: Marcin Mincer spółka cywilna/), text_of(pdf_for_user)
  end

  context "data pack purchases" do
    test "shows on receipts when purchased" do
      @billing_transaction.transaction_type = "prorate-asset-pack-charge"
      @billing_transaction.asset_packs_delta = 1
      @billing_transaction.asset_packs_total = 1
      @billing_transaction.service_ends_at   = (@now + 10.days).beginning_of_day
      assert_match "1 additional data pack ($5/month each - prorated for 11 days)", text_of(pdf_for_user)
    end

    test "doesn't show if no seat packs" do
      refute_match "data pack", text_of(pdf_for_user)
    end
  end

  context "with sponsorships" do
    test "shows recurring sponsorship without fee on the receipt" do
      sponsors_tier = create(:sponsors_tier, :approved_sponsors_listing, monthly_price_in_cents: 7_00)
      @billing_transaction.update(plan_name: "free", amount_in_cents: sponsors_tier.monthly_price_in_cents)
      sponsors_listing = sponsors_tier.sponsors_listing
      create(:billing_transaction_line_item, :sponsors, subscribable: sponsors_tier,
        billing_transaction: @billing_transaction)

      text = text_of(pdf_for_user)

      assert_includes text, "Sponsorship Amount"
      refute_includes text, "Sponsorship Fees"
      assert_includes text, "Thanks for your support of Open Source Software!"
      assert_includes text, "for your sponsorship."
      assert_includes text, "#{sponsors_listing.slug.delete_prefix("sponsors-")} - $7 a month"
      assert_match /Sponsorship Amount\s+\$7\.00 USD/, text
    end

    test "shows recurring sponsorship with fee on the receipt" do
      sponsors_tier = create(:sponsors_tier, :approved_sponsors_listing, monthly_price_in_cents: 7_00)
      sponsors_listing = sponsors_tier.sponsors_listing
      non_fee_line_item = create(:billing_transaction_line_item, :sponsors, subscribable: sponsors_tier,
        billing_transaction: @per_seat_billing_transaction)
      fee_line_item = create(:billing_transaction_line_item, :sponsors_fee, subscribable: sponsors_tier,
        billing_transaction: @per_seat_billing_transaction)
      @per_seat_billing_transaction.update(plan_name: "free",
        amount_in_cents: non_fee_line_item.amount_in_cents + fee_line_item.amount_in_cents)

      text = text_of(pdf_for_org)

      assert_includes text, "Sponsorship Amount"
      assert_includes text, "Thanks for your support of Open Source Software!"
      assert_includes text, "for your sponsorship."
      assert_includes text, "#{sponsors_listing.slug.delete_prefix("sponsors-")} - $7 a month"
      assert_match /#{sponsors_listing.slug.delete_prefix("sponsors-")} - \$7 a month - fee\s+\(\$0\.42\)/, text
      assert_match /Sponsorship Amount\s+\$7\.00 USD/, text
      assert_match /Sponsorship Fees\s+\$0\.42 USD/, text
    end

    test "shows one-time sponsorship without fee on the receipt" do
      sponsors_tier = create(:sponsors_tier, :approved_sponsors_listing, :one_time, monthly_price_in_cents: 15_00)
      @billing_transaction.update(plan_name: "free", amount_in_cents: sponsors_tier.monthly_price_in_cents)
      sponsors_listing = sponsors_tier.sponsors_listing
      create(:billing_transaction_line_item, :sponsors, subscribable: sponsors_tier,
        billing_transaction: @billing_transaction)

      text = text_of(pdf_for_user)

      assert_includes text, "Sponsorship Amount"
      refute_includes text, "Sponsorship Fees"
      assert_includes text, "Thanks for your support of Open Source Software!"
      assert_includes text, "for your sponsorship."
      assert_includes text, "#{sponsors_listing.slug.delete_prefix("sponsors-")} - $15 one time"
      assert_match /Sponsorship Amount\s+\$15\.00 USD/, text
    end

    test "shows one-time sponsorship with fee on the receipt" do
      sponsors_tier = create(:sponsors_tier, :approved_sponsors_listing, :one_time, monthly_price_in_cents: 30_00)
      non_fee_line_item = create(:billing_transaction_line_item, :sponsors, subscribable: sponsors_tier,
        billing_transaction: @per_seat_billing_transaction)
      fee_line_item = create(:billing_transaction_line_item, :sponsors_fee, subscribable: sponsors_tier,
        billing_transaction: @per_seat_billing_transaction)
      @per_seat_billing_transaction.update(plan_name: "free",
        amount_in_cents: non_fee_line_item.amount_in_cents + fee_line_item.amount_in_cents)
      sponsors_listing = sponsors_tier.sponsors_listing

      text = text_of(pdf_for_org)

      assert_includes text, "Sponsorship Amount"
      assert_includes text, "Thanks for your support of Open Source Software!"
      assert_includes text, "for your sponsorship."
      assert_includes text, "#{sponsors_listing.slug.delete_prefix("sponsors-")} - $30 one time"
      assert_match /#{sponsors_listing.slug.delete_prefix("sponsors-")} - \$30 one time - fee\s+\(\$1\.80\)/, text
      assert_match /Sponsorship Amount\s+\$30\.00 USD/, text
      assert_match /Sponsorship Fees\s+\$1\.80 USD/, text
    end

    test "shows multiple sponsorships with fees on the receipt" do
      sponsors_tier1 = create(:sponsors_tier, :approved_sponsors_listing, :one_time, monthly_price_in_cents: 30_00)
      non_fee_line_item1 = create(:billing_transaction_line_item, :sponsors, subscribable: sponsors_tier1,
        billing_transaction: @per_seat_billing_transaction)
      fee_line_item1 = create(:billing_transaction_line_item, :sponsors_fee, subscribable: sponsors_tier1,
        billing_transaction: @per_seat_billing_transaction)

      sponsors_tier2 = create(:sponsors_tier, :approved_sponsors_listing, monthly_price_in_cents: 12_00)
      non_fee_line_item2 = create(:billing_transaction_line_item, :sponsors, subscribable: sponsors_tier2,
        billing_transaction: @per_seat_billing_transaction)
      fee_line_item2 = create(:billing_transaction_line_item, :sponsors_fee, subscribable: sponsors_tier2,
        billing_transaction: @per_seat_billing_transaction)

      @per_seat_billing_transaction.update(plan_name: "free", amount_in_cents: non_fee_line_item1.amount_in_cents +
        fee_line_item1.amount_in_cents + non_fee_line_item2.amount_in_cents + fee_line_item2.amount_in_cents)
      sponsors_listing1 = sponsors_tier1.sponsors_listing
      sponsors_listing2 = sponsors_tier2.sponsors_listing

      text = text_of(pdf_for_org)

      assert_includes text, "Sponsorship Amount"
      assert_includes text, "Thanks for your support of Open Source Software!"
      assert_includes text, "for your sponsorships."
      assert_includes text, "#{sponsors_listing1.slug.delete_prefix("sponsors-")} - $30 one time"
      assert_includes text, "#{sponsors_listing2.slug.delete_prefix("sponsors-")} - $12 a month"
      assert_match /#{sponsors_listing1.slug.delete_prefix("sponsors-")} - \$30 one time - fee\s+\(\$1\.80\)/, text
      assert_match /#{sponsors_listing2.slug.delete_prefix("sponsors-")} - \$12 a month - fee\s+\(\$0\.72\)/, text
      assert_match /Sponsorship Amount\s+\$42\.00 USD/, text
      assert_match /Sponsorship Fees\s+\$2\.52 USD/, text
    end

    test "shows nothing if no sponsorships" do
      refute_match "Sponsorship Amount", text_of(pdf_for_user)
    end
  end

  context "with refund" do
    test "shows refund-specific content on the receipt" do
      @billing_transaction.update(
        plan_name: "free",
        amount_in_cents: -8_00,
        prorated_days: 0,
        sale_transaction_id: "123abc"
      )

      text = text_of(pdf_for_user)

      assert_includes text, "You've been issued a refund!"
      assert_includes text, "Refund Amount"
      assert_match "$8.00", text_of(pdf_for_user)
      assert_includes text, "Sale Transaction ID"
      assert_match "123abc", text_of(pdf_for_user)
    end
  end

  context "with copilot purchases" do
    test "monthly subscription shows on the receipt" do
      @billing_transaction.update(plan_name: "free", amount_in_cents: 10_00)

      li = create(
        :billing_transaction_line_item,
        :copilot_for_individual_month,
        billing_transaction: @billing_transaction,
        amount_in_cents: 5_00,
      )

      assert_match "Copilot", text_of(pdf_for_user)
      assert_match "/month", text_of(pdf_for_user)
      assert_match li.formatted_service_period(format: Billing::Receipt::PdfRenderer::SERVICE_DATES_FORMAT, separator: "-"), text_of(pdf_for_user)
    end

    test "monthly subscription shows proration on the receipt" do
      @billing_transaction.update(plan_name: "free", amount_in_cents: 10_00, prorated_days: 8, transaction_type: "prorate-charge")
      li = create(
        :billing_transaction_line_item,
        :copilot_for_individual_month,
        billing_transaction: @billing_transaction,
        amount_in_cents: 5_00,
      )

      assert_match "Copilot", text_of(pdf_for_user)
      assert_match "$5.00 ($10/month - prorated for 8 days", text_of(pdf_for_user)
      assert_match li.formatted_service_period(format: Billing::Receipt::PdfRenderer::SERVICE_DATES_FORMAT, separator: "-"), text_of(pdf_for_user)
    end

    test "yearly subscription shows proration on the receipt" do
      @billing_transaction.update(plan_name: "free", amount_in_cents: 10_00, prorated_days: 45, transaction_type: "prorate-charge")
      copilot_yearly_product_uuid = create(:billing_product_uuid, :copilot, billing_cycle: :year)

      li = create(:billing_transaction_line_item,
        billing_transaction: @billing_transaction,
        subscribable: copilot_yearly_product_uuid,
        amount_in_cents: 85_00,
        quantity: 1,
        description: "GitHub Copilot",
        subscribable_type: Billing::ProductUUID.name
      )

      assert_match "Copilot", text_of(pdf_for_user)
      assert_match "$85.00 ($100/year - prorated for 45 days", text_of(pdf_for_user)
      assert_match li.formatted_service_period(format: Billing::Receipt::PdfRenderer::SERVICE_DATES_FORMAT, separator: "-"), text_of(pdf_for_user)
    end

    test "shows nothing if no copilot purchases" do
      refute_match "Copilot", text_of(pdf_for_user)
    end
  end

  context "with advanced security purchases" do
    test "monthly subscription with 1 seat shows on the receipt" do
      @billing_transaction.update(plan_name: "business_plus", amount_in_cents: 19_00)

      @ghas_monthly_product_uuid = create(:billing_product_uuid, :advanced_security, billing_cycle: :month)

      li = create(
        :billing_transaction_line_item,
        billing_transaction: @billing_transaction,
        subscribable: @ghas_monthly_product_uuid,
        amount_in_cents: 19_00,
        quantity: 1,
        description: "GitHub Advanced Security",
        subscribable_type: Billing::ProductUUID.name
      )

      assert_match "Advanced Security", text_of(pdf_for_user)
      assert_match "1 seat ($49/month each)", text_of(pdf_for_user)
      assert_match li.formatted_service_period(format: Billing::Receipt::PdfRenderer::SERVICE_DATES_FORMAT, separator: "-"), text_of(pdf_for_user)
    end

    test "monthly subscription with multiple seats without proration shows on the receipt" do
      @billing_transaction.update(plan_name: "business_plus", amount_in_cents: 19_00)

      ghas_monthly_product_uuid = create(:billing_product_uuid, :advanced_security, billing_cycle: :month)

      li = create(:billing_transaction_line_item,
          billing_transaction: @billing_transaction,
          subscribable: ghas_monthly_product_uuid,
          amount_in_cents: 100_00,
          quantity: 18,
          description: "GitHub Advanced Security",
          subscribable_type: Billing::ProductUUID.name
        )

      assert_match "Advanced Security", text_of(pdf_for_user)
      assert_match "18 seats ($49/month each)", text_of(pdf_for_user)
      assert_match li.formatted_service_period(format: Billing::Receipt::PdfRenderer::SERVICE_DATES_FORMAT, separator: "-"), text_of(pdf_for_user)
    end

    test "monthly subscription shows proration on the receipt" do
      @billing_transaction.update(plan_name: "business_plus", amount_in_cents: 19_00, prorated_days: 8, transaction_type: "prorate-charge")
      @ghas_monthly_product_uuid = create(:billing_product_uuid, :advanced_security, billing_cycle: :month)

      li = create(:billing_transaction_line_item,
          billing_transaction: @billing_transaction,
          subscribable: @ghas_monthly_product_uuid,
          amount_in_cents: 13_00,
          quantity: 1,
          description: "GitHub Advanced Security",
          subscribable_type: Billing::ProductUUID.name
        )

      assert_match "Advanced Security", text_of(pdf_for_user)
      assert_match "1 seat ($49/month each - prorated for 8 days", text_of(pdf_for_user)
      assert_match li.formatted_service_period(format: Billing::Receipt::PdfRenderer::SERVICE_DATES_FORMAT, separator: "-"), text_of(pdf_for_user)
    end

    test "shows nothing if no advanced security purchased" do
      refute_match "Advanced Security", text_of(pdf_for_user)
    end

    test "shows no other subscribables" do
      @billing_transaction.update(plan_name: "business_plus", amount_in_cents: 19_00, prorated_days: 8, transaction_type: "prorate-charge")
      @ghas_monthly_product_uuid = create(:billing_product_uuid, :advanced_security, billing_cycle: :month)

      create(:billing_transaction_line_item,
          billing_transaction: @billing_transaction,
          subscribable: @ghas_monthly_product_uuid,
          amount_in_cents: 13_00,
          quantity: 1,
          description: "GitHub Advanced Security",
          subscribable_type: Billing::ProductUUID.name
        )

      assert_match "Advanced Security", text_of(pdf_for_user)
      refute_match "Copilot", text_of(pdf_for_user)
    end
  end

  context "with marketplace purchases" do
    test "shows on the receipt" do
      listing = create :marketplace_listing, :verified,
        name: "TravisCI"
      listing_plan = create :marketplace_listing_plan,
        listing: listing,
        name: "Standard"
      create :billing_transaction_line_item,
        subscribable: listing_plan,
        listing: listing,
        billing_transaction: @billing_transaction

      assert_match "Marketplace Apps", text_of(pdf_for_user)
      assert_match "TravisCI - Standard", text_of(pdf_for_user)
    end

    test "shows nothing if no marketplace purchases" do
      refute_match "Marketplace Apps", text_of(pdf_for_user)
    end
  end

  context "actions usage overage charges" do
    test "shows on the receipt" do
      create :billing_transaction_line_item,
        :actions_private_usage,
        quantity: 3_000,
        amount_in_cents: 0,
        billing_transaction: @billing_transaction
      li = create :billing_transaction_line_item,
        :actions_private_usage,
        quantity: 100,
        amount_in_cents: 80,
        billing_transaction: @billing_transaction

      assert_match "GitHub Actions", text_of(pdf_for_user)
      assert_match "3000 included private minutes $0.00 USD", text_of(pdf_for_user)
      assert_match "100 additional private minutes $0.80 USD", text_of(pdf_for_user)
      assert_match li.formatted_service_period(format: Billing::Receipt::PdfRenderer::SERVICE_DATES_FORMAT, separator: "-"), text_of(pdf_for_user)
    end
  end

  context "with package registry transfer overages" do
    test "shows on the receipt" do
      create :billing_transaction_line_item,
        :package_registry_data_usage,
        quantity: 5,
        amount_in_cents: 0,
        billing_transaction: @billing_transaction
      li = create :billing_transaction_line_item,
        :package_registry_data_usage,
        quantity: 3,
        amount_in_cents: 1_50,
        billing_transaction: @billing_transaction

      assert_match "GitHub Packages", text_of(pdf_for_user)
      assert_match "5GB included data transfer out $0.00 USD", text_of(pdf_for_user)
      assert_match "3GB additional data transfer out $1.50 USD", text_of(pdf_for_user)
      assert_match li.formatted_service_period(format: Billing::Receipt::PdfRenderer::SERVICE_DATES_FORMAT, separator: "-"), text_of(pdf_for_user)
    end

    test "does not show with no charges" do
      refute_match "GitHub Packages", text_of(pdf_for_user)
    end
  end

  context "with shared storage overages" do
    test "shows on the receipt" do
      create :billing_transaction_line_item,
        :shared_storage,
        quantity: 761_856, # 1024MB of usage
        amount_in_cents: 0,
        billing_transaction: @billing_transaction

      li = create :billing_transaction_line_item,
        :shared_storage,
        quantity: 761_856, # 1024MB of usage
        amount_in_cents: 25,
        billing_transaction: @billing_transaction

      assert_match "Actions/Packages Storage", text_of(pdf_for_user)
      assert_match "1.0GB included storage $0.00 USD", text_of(pdf_for_user)
      assert_match "1.0GB additional storage $0.25 USD", text_of(pdf_for_user)
      assert_match li.formatted_service_period(format: Billing::Receipt::PdfRenderer::SERVICE_DATES_FORMAT, separator: "-"), text_of(pdf_for_user)
    end

    test "does not show with no charges" do
      refute_match "Storage for Actions and Packages", text_of(pdf_for_user)
    end
  end

  context "with codespaces usage" do
    test "does not show included usage on the receipt" do
      @billing_transaction.update(plan_name: "pro")
      create :billing_transaction_line_item,
        :codespaces_storage_usage,
        quantity: 160,
        amount_in_cents: 0,
        billing_transaction: @billing_transaction

      create :billing_transaction_line_item,
        :codespaces_compute_d2_usage,
        quantity: 10,
        amount_in_cents: 0,
        billing_transaction: @billing_transaction

      text = text_of(Billing::Receipt::PdfRenderer.new(Billing::Receipt.new(@billing_transaction)))
      refute_match "Codespaces", text
      refute_match "included", text
    end

    test "shows overage usage on the receipt" do
      @billing_transaction.update(plan_name: "pro")
      create :billing_transaction_line_item,
        :codespaces_storage_usage,
        quantity: 160,
        amount_in_cents: 0,
        billing_transaction: @billing_transaction

      create :billing_transaction_line_item,
        :codespaces_storage_usage,
        quantity: 30,
        amount_in_cents: 20_00,
        billing_transaction: @billing_transaction

      create :billing_transaction_line_item,
        :codespaces_compute_d2_usage,
        quantity: 10,
        amount_in_cents: 0,
        billing_transaction: @billing_transaction

      li = create :billing_transaction_line_item,
        :codespaces_compute_d2_usage,
        quantity: 5,
        amount_in_cents: 25_00,
        billing_transaction: @billing_transaction

      text = text_of(Billing::Receipt::PdfRenderer.new(Billing::Receipt.new(@billing_transaction)))

      assert_match "Codespaces Amount", text
      assert_match "$45.00 USD", text
      assert_match "Codespaces", text
      assert_match "5 hours of compute (2 core)", text
      assert_match "30GB of storage", text
      assert_match li.formatted_service_period(format: Billing::Receipt::PdfRenderer::SERVICE_DATES_FORMAT, separator: "-"), text_of(pdf_for_user)
    end

    test "codespaces compute does not show but storage does" do
      @billing_transaction.update(plan_name: "pro")
      create :billing_transaction_line_item,
        :codespaces_storage_usage,
        quantity: 160,
        amount_in_cents: 0,
        billing_transaction: @billing_transaction

      li = create :billing_transaction_line_item,
        :codespaces_storage_usage,
        quantity: 30,
        amount_in_cents: 20_00,
        billing_transaction: @billing_transaction

      text = text_of(pdf_for_user)
      refute_match "compute", text
      assert_match "Codespaces", text
      assert_match "30GB of storage", text
      assert_match %r{Codespaces Amount\s*\$20.00 USD}, text
      assert_match li.formatted_service_period(format: Billing::Receipt::PdfRenderer::SERVICE_DATES_FORMAT, separator: "-"), text_of(pdf_for_user)
    end

    test "does not show with no charges" do
      refute_match "Codespaces", text_of(pdf_for_user)
    end
  end

  context "Copilot Business usage charges" do
    test "shows on the receipt" do
      organization = create(:copilot_for_business_enabled_organization)

      li = create :billing_transaction_line_item,
        :copilot_for_business_usage,
        user: organization,
        quantity: 1.234567890,
        amount_in_cents: 23_46, # 1.234567890 users * $19.00/user
        billing_transaction: @billing_transaction,
        extras: { "unit_price" => 19, "prorations" => [{ "days" => 14, "count" => 3 }] }

      assert_match "GitHub Copilot", text_of(pdf_for_user)
      assert_match "3 seats ($19/month each - prorated for 14 days)", text_of(pdf_for_user)
      assert_match li.formatted_service_period(format: Billing::Receipt::PdfRenderer::SERVICE_DATES_FORMAT, separator: "-"), text_of(pdf_for_user)
    end

    test "does not show on the receipt for a user with Copilot Business disabled" do
      # by default the user does not have Copilot Business enabled
      create :billing_transaction_line_item,
        :copilot_for_business_usage,
        quantity: 1.234567890,
        amount_in_cents: 23_46, # 1.234567890 users * $19.00/user
        billing_transaction: @billing_transaction

      refute_match "GitHub Copilot", text_of(pdf_for_user)
      if GitHub.flipper[:copilot_for_business_receipt_breakdown].enabled?
        refute_match "1.2346 total billed seats", text_of(pdf_for_user)
      else
        refute_match "1.2346 seats $23.46 USD", text_of(pdf_for_user)
      end
    end

    test "shows with other Copilot skus usage" do
      create :billing_product_uuid, :copilot_enterprise
      organization = create(:copilot_for_business_enabled_organization)
      create :billing_transaction_line_item,
        :copilot_for_business_usage,
        user: organization,
        quantity: 1,
        amount_in_cents: 19_00,
        billing_transaction: @billing_transaction,
        extras: { "unit_price" => 19, "prorations" => [{ "days" => 14, "count" => 1 }], "seats_billed_in_full" => 2 }

      create :billing_transaction_line_item,
        :copilot_enterprise_usage,
        user: organization,
        quantity: 1,
        amount_in_cents: 39_00,
        billing_transaction: @billing_transaction
      create :billing_transaction_line_item,
        :copilot_enterprise_usage,
        user: organization,
        quantity: 4,
        amount_in_cents: 39_00,
        billing_transaction: @billing_transaction
      create :billing_transaction_line_item,
        :copilot_enterprise_usage,
        user: organization,
        quantity: 50,
        amount_in_cents: 39_00,
        billing_transaction: @billing_transaction

      pdf_text = text_of(pdf_for_user)
      assert_match "GitHub Copilot", pdf_text
      assert_match "GitHub Copilot Amount", pdf_text
      assert_match "Business:", pdf_text
      assert_match "2 seats ($19/month each)", pdf_text
      assert_match "1 seat ($19/month each - prorated for 14 days)", pdf_text
      assert_match "1 billed seat ($19/month each)", pdf_text
      assert_match "Enterprise:", pdf_text
      assert_match "55 billed seats ($39/month each)", pdf_text

      li = @billing_transaction.line_items.metered_copilot_usage.detect(&:service_period?)
      assert_match li.formatted_service_period(format: Billing::Receipt::PdfRenderer::SERVICE_DATES_FORMAT, separator: "-"), pdf_text
    end
  end
end
