# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::BillingTransaction::SponsorsDependencyTest < GitHub::TestCase
  include AuditLog::IntegrationTestHelpers
  include HydroTestHelpers

  fixtures do
    @sponsors_tier = create(:sponsors_tier, :approved_sponsors_listing)
    @user = create(:credit_card_user, billed_on: ::GitHub::Billing.today + 1.day,
      plan_subscription: create(:billing_plan_subscription))
    @plan_subscription = @user.plan_subscription
  end

  setup do
    skip unless GitHub.sponsors_enabled?
  end

  context "#log_recurring_charge" do
    test "uses the invoice amount for a matching SponsorsTier-based Zuora product subscription item" do
      sub_item = create(:sponsors_subscription_item)
      published_tier = sub_item.subscribable
      listing = sub_item.listing
      user = sub_item.user
      plan_subscription = sub_item.plan_subscription

      charge_name = "#{listing.slug}: #{published_tier.name}"

      service_start_date = "2022-09-22"
      service_end_date = "2022-10-21"
      invoiced_items = [
        Billing::Zuora::InvoiceItem.new(
          "chargeId" => SecureRandom.alphanumeric(32),
          "chargeName" => "#{charge_name} - month",
          "chargeAmount" => 12.11,
          "quantity" => 1.0,
          "serviceStartDate" => service_start_date,
          "serviceEndDate" => service_end_date,
          "productRatePlanChargeId" => SecureRandom.alphanumeric(32)
        ),
      ]

      billing_transaction = Billing::BillingTransaction.new(
        amount_in_cents: 40_00,
        plan_subscription: plan_subscription,
      )

      # The first line item is for a SponsorsTier
      assert_difference "Billing::BillingTransaction::LineItem.count", 1 do
        billing_transaction.log_recurring_charge \
          billable_entity: user,
          invoiced_items: invoiced_items,
          charge_type: "prorate-charge"
      end
      billing_transaction.reload

      assert_equal 1, published_tier.reload.billing_transaction_line_items.count
      assert_equal 1, billing_transaction.line_items.sponsorships.count

      # When "billable" invoice items exist, the billable line item(s) are created first
      sponsors_line_item = billing_transaction.line_items.first
      assert_equal 12_11, T.must(sponsors_line_item).amount_in_cents
      assert_equal "prorate-charge", billing_transaction.transaction_type
      assert_equal listing, T.must(sponsors_line_item).listing
      assert_equal service_start_date, T.must(sponsors_line_item).service_start_date.to_s
      assert_equal service_end_date, T.must(sponsors_line_item).service_end_date.to_s
    end

    test "uses the invoice amount for a matching SponsorsListing-based Zuora product subscription item when user is not in the flag" do
      sub_item = create(:sponsors_subscription_item)
      user = sub_item.user
      plan_subscription = sub_item.plan_subscription
      published_tier = sub_item.subscribable
      listing = published_tier.sponsors_listing

      service_start_date = "2022-09-22"
      service_end_date = "2022-10-21"
      matching_charge_id = SecureRandom.alphanumeric(32)
      matching_product_rate_plan_charge_id = SecureRandom.alphanumeric(32)
      invoiced_items = [
        Billing::Zuora::InvoiceItem.new(
          "chargeId" => SecureRandom.alphanumeric(32),
          "unitPrice" => 10,
          "chargeName" => "Not a matching charge name",
          "chargeAmount" => 40.00,
          "quantity" => 1.0,
          "serviceStartDate" => service_start_date,
          "serviceEndDate" => service_end_date,
          "productRatePlanChargeId" => SecureRandom.alphanumeric(32)
        ),
        Billing::Zuora::InvoiceItem.new(
          "chargeId" => matching_charge_id,
          "unitPrice" => published_tier.monthly_price_in_cents / 100,
          "chargeName" => listing.monthly_plan_or_charge_name,
          "chargeAmount" => 12.11,
          "quantity" => 1.0,
          "serviceStartDate" => service_start_date,
          "serviceEndDate" => service_end_date,
          "productRatePlanChargeId" => matching_product_rate_plan_charge_id
        ),
        Billing::Zuora::InvoiceItem.new(
          "chargeId" => matching_charge_id,
          "unitPrice" => published_tier.monthly_price_in_cents / 100,
          "chargeName" => listing.monthly_plan_or_charge_name,
          "chargeAmount" => 7.89,
          "quantity" => 1.0,
          "serviceStartDate" => service_start_date,
          "serviceEndDate" => service_end_date,
          "productRatePlanChargeId" => matching_product_rate_plan_charge_id
        ),
      ]

      billing_transaction = Billing::BillingTransaction.new(
        amount_in_cents: 40_00,
        plan_subscription: plan_subscription,
      )

      assert_difference "Billing::BillingTransaction::LineItem.count", 2 do
        billing_transaction.log_recurring_charge \
          billable_entity: user,
          invoiced_items: invoiced_items,
          charge_type: "prorate-charge"
      end
      billing_transaction.reload

      assert_equal 1, published_tier.reload.billing_transaction_line_items.count
      assert_equal 1, billing_transaction.line_items.sponsorships.count
      # 20_00 is the sum of both Sponsors invoice items' charge_amounts in cents
      sponsors_line_item = billing_transaction.line_items.sponsorships.first
      assert_equal published_tier, T.must(sponsors_line_item).subscribable
      assert_equal 20_00, T.must(sponsors_line_item).amount_in_cents
      assert_equal "#{listing.name} - #{published_tier.name}", T.must(sponsors_line_item).description
      assert_equal "prorate-charge", billing_transaction.transaction_type
      assert_equal service_start_date, T.must(sponsors_line_item).service_start_date.to_s
      assert_equal service_end_date, T.must(sponsors_line_item).service_end_date.to_s
    end

    test "emits Hydro sponsorship payment complete message when adding a concurrent one-time payment" do
      recurring_tier = create(:sponsors_tier, :approved_sponsors_listing)
      sponsorable = recurring_tier.sponsorable
      sponsors_listing = recurring_tier.sponsors_listing
      one_time_tier = create(:sponsors_tier, :published, :one_time, monthly_price_in_cents: 5_00,
        sponsors_listing: sponsors_listing)
      existing_sponsorship = create(:sponsorship, tier: recurring_tier)
      sponsor = existing_sponsorship.sponsor
      plan_subscription = existing_sponsorship.plan_subscription
      one_time_sub_item = create(:sponsors_subscription_item,
        account: sponsor, subscribable: one_time_tier)
      assert_equal 2, plan_subscription.subscription_items.count
      service_start_date = "2022-09-22"
      service_end_date = "2022-10-21"
      invoiced_items = [
        Billing::Zuora::SubscribableInvoiceItem.new({
          "chargeId" => SecureRandom.alphanumeric(32),
          "unitPrice" => 5,
          "chargeName" => sponsors_listing.monthly_plan_or_charge_name,
          "chargeAmount" => 5.00,
          "quantity" => 1,
          "serviceStartDate" => service_start_date,
          "serviceEndDate" => service_end_date,
          "productRatePlanChargeId" => SecureRandom.alphanumeric(32),
        }, subscribable: one_time_tier),
      ]
      billing_transaction = Billing::BillingTransaction.new(
        amount_in_cents: 5_00,
        plan_subscription: plan_subscription,
      )

      assert_hydro_message_difference("github.sponsors.v1.SponsorshipPaymentComplete", 1) do
        assert_difference("Billing::BillingTransaction::LineItem.count") do
          billing_transaction.log_recurring_charge(
            billable_entity: sponsor,
            invoiced_items: invoiced_items,
            charge_type: "prorate-charge",
          )
        end
      end

      assert_equal 1, billing_transaction.reload.line_items.sponsorships.count
      assert_equal "prorate-charge", billing_transaction.transaction_type
      assert_equal 1, one_time_tier.reload.billing_transaction_line_items.count

      sponsors_line_item = billing_transaction.line_items.find_by(subscribable: one_time_tier)
      refute_nil sponsors_line_item
      assert_equal 5_00, T.must(sponsors_line_item).amount_in_cents
      assert_equal "#{sponsors_listing.name} - #{one_time_tier.name}", T.must(sponsors_line_item).description
      assert_equal service_start_date, T.must(sponsors_line_item).service_start_date.to_s
      assert_equal service_end_date, T.must(sponsors_line_item).service_end_date.to_s

      assert_hydro_published_partial({
        sponsorship: Hydro::EntitySerializer.sponsorship(existing_sponsorship),
        listing: Hydro::EntitySerializer.sponsors_listing(one_time_tier.sponsors_listing),
        tier: Hydro::EntitySerializer.sponsors_tier(one_time_tier),
        via_bulk_sponsorship: false,
      }, schema: "github.sponsors.v1.SponsorshipPaymentComplete")
    end

    # https://github.com/github/sponsors/issues/5420
    test "does not emit Hydro event for nonexistent org for a self-serve enterprise sponsorship" do
      sub_item = create(:sponsors_subscription_item, :self_serve_business)
      listing = sub_item.listing
      tier = sub_item.sponsors_tier
      plan_subscription = sub_item.plan_subscription
      business = plan_subscription.billable_entity
      member_org = sub_item.organization

      doomed_member_org = create(:organization, business: business)
      doomed_member_org_sub_item = create(:sponsors_subscription_item, account: doomed_member_org, subscribable: tier)

      sponsorship = create(:sponsorship, :unpaid, sponsor: member_org, tier: tier, subscription_item: sub_item)
      doomed_member_org_sponsorship = create(:sponsorship, :unpaid, sponsor: doomed_member_org, tier: tier,
        subscription_item: doomed_member_org_sub_item)
      transaction = create(:billing_transaction, :business_owned, plan_subscription: plan_subscription,
        amount_in_cents: tier.monthly_price_in_cents * 2)

      doomed_member_org.delete

      assert_hydro_message_difference("github.sponsors.v1.SponsorshipPaymentComplete", 1) do
        transaction.log_recurring_charge(
          billable_entity: business,
          invoiced_items: [
            Billing::Zuora::SubscribableInvoiceItem.new({
              "chargeId" => SecureRandom.alphanumeric(32),
              "chargeName" => listing.monthly_plan_or_charge_name,
              "chargeAmount" => tier.monthly_price_in_dollars,
              "quantity" => 1,
              "serviceStartDate" => Time.now.to_formatted_s(:date),
              "serviceEndDate" => (Time.now + 1.month).to_formatted_s(:date),
              "productRatePlanChargeId" => SecureRandom.alphanumeric(32),
            }, subscription_item: sub_item),
            Billing::Zuora::SubscribableInvoiceItem.new({
              "chargeId" => SecureRandom.alphanumeric(32),
              "chargeName" => listing.monthly_plan_or_charge_name,
              "chargeAmount" => tier.monthly_price_in_dollars,
              "quantity" => 1,
              "serviceStartDate" => Time.now.to_formatted_s(:date),
              "serviceEndDate" => (Time.now + 1.month).to_formatted_s(:date),
              "productRatePlanChargeId" => SecureRandom.alphanumeric(32),
            }, subscription_item: doomed_member_org_sub_item),
          ]
        )
      end

      assert_hydro_published_partial({
        sponsorship: Hydro::EntitySerializer.sponsorship(sponsorship),
        listing: Hydro::EntitySerializer.sponsors_listing(listing),
        tier: Hydro::EntitySerializer.sponsors_tier(tier),
        actor: Hydro::EntitySerializer.user(member_org),
        via_bulk_sponsorship: false,
      }, schema: "github.sponsors.v1.SponsorshipPaymentComplete")
    end

    test "emits Hydro sponsorship payment complete messages with via_bulk_sponsorship=true when the sponsorship tier is stored in GitHub KV" do
      one_time_tier1, one_time_tier2 = create_pair(:sponsors_tier, :approved_sponsors_listing, :one_time,
        monthly_price_in_cents: 5_00)
      listing1 = one_time_tier1.sponsors_listing
      listing2 = one_time_tier2.sponsors_listing
      sponsorship1 = create(:sponsorship, tier: one_time_tier1)
      sponsor = sponsorship1.sponsor
      plan_subscription = sponsorship1.plan_subscription
      sponsorship2 = create(:sponsorship, sponsor: sponsor, tier: one_time_tier2)
      assert_equal 2, plan_subscription.subscription_items.count,
        "should have a subscription item for each sponsorship"
      sponsor.save_bulk_sponsorship_tier_ids([one_time_tier1.id, one_time_tier2.id])
      service_start_date = "2022-09-22"
      service_end_date = "2022-10-21"
      invoiced_items = [
        Billing::Zuora::SubscribableInvoiceItem.new({
          "chargeId" => SecureRandom.alphanumeric(32),
          "unitPrice" => 5,
          "chargeName" => listing1.monthly_plan_or_charge_name,
          "chargeAmount" => 5.00,
          "quantity" => 1,
          "serviceStartDate" => service_start_date,
          "serviceEndDate" => service_end_date,
          "productRatePlanChargeId" => SecureRandom.alphanumeric(32),
        }, subscribable: one_time_tier1),
        Billing::Zuora::SubscribableInvoiceItem.new({
          "chargeId" => SecureRandom.alphanumeric(32),
          "unitPrice" => 5,
          "chargeName" => listing2.monthly_plan_or_charge_name,
          "chargeAmount" => 5.00,
          "quantity" => 1,
          "serviceStartDate" => service_start_date,
          "serviceEndDate" => service_end_date,
          "productRatePlanChargeId" => SecureRandom.alphanumeric(32),
        }, subscribable: one_time_tier2),
      ]
      billing_transaction = Billing::BillingTransaction.new(
        amount_in_cents: 10_00,
        plan_subscription: plan_subscription,
      )

      assert_hydro_message_difference("github.sponsors.v1.SponsorshipPaymentComplete", 2) do
        assert_difference("Billing::BillingTransaction::LineItem.count", 2) do
          billing_transaction.log_recurring_charge(
            billable_entity: sponsor,
            invoiced_items: invoiced_items,
            charge_type: "prorate-charge",
          )
        end
      end

      assert_equal 2, billing_transaction.reload.line_items.sponsorships.count
      assert_equal "prorate-charge", billing_transaction.transaction_type
      assert_equal 1, one_time_tier1.reload.billing_transaction_line_items.count
      assert_equal 1, one_time_tier2.reload.billing_transaction_line_items.count

      sponsors_line_item1 = billing_transaction.line_items.find_by(subscribable: one_time_tier1)
      refute_nil sponsors_line_item1
      assert_equal 5_00, T.must(sponsors_line_item1).amount_in_cents
      assert_equal "#{listing1.name} - #{one_time_tier1.name}", T.must(sponsors_line_item1).description
      assert_equal service_start_date, T.must(sponsors_line_item1).service_start_date.to_s
      assert_equal service_end_date, T.must(sponsors_line_item1).service_end_date.to_s

      sponsors_line_item2 = billing_transaction.line_items.find_by(subscribable: one_time_tier2)
      refute_nil sponsors_line_item2
      assert_equal 5_00, T.must(sponsors_line_item2).amount_in_cents
      assert_equal "#{listing2.name} - #{one_time_tier2.name}", T.must(sponsors_line_item2).description
      assert_equal service_start_date, T.must(sponsors_line_item2).service_start_date.to_s
      assert_equal service_end_date, T.must(sponsors_line_item2).service_end_date.to_s

      assert_hydro_published_partial({
        sponsorship: Hydro::EntitySerializer.sponsorship(sponsorship1),
        listing: Hydro::EntitySerializer.sponsors_listing(one_time_tier1.sponsors_listing),
        tier: Hydro::EntitySerializer.sponsors_tier(one_time_tier1),
        via_bulk_sponsorship: true,
      }, schema: "github.sponsors.v1.SponsorshipPaymentComplete")

      assert_hydro_published_partial({
        sponsorship: Hydro::EntitySerializer.sponsorship(sponsorship2),
        listing: Hydro::EntitySerializer.sponsors_listing(one_time_tier2.sponsors_listing),
        tier: Hydro::EntitySerializer.sponsors_tier(one_time_tier2),
        via_bulk_sponsorship: true,
      }, schema: "github.sponsors.v1.SponsorshipPaymentComplete")
    end

    test "emits Hydro sponsorship payment complete messages with via_bulk_sponsorship=false when the sponsorship tier is not stored in GitHub KV" do
      one_time_tier = create(:sponsors_tier, :approved_sponsors_listing, :one_time, monthly_price_in_cents: 5_00)
      recurring_tier = create(:sponsors_tier, :approved_sponsors_listing, monthly_price_in_cents: 5_00)
      one_time_tier_listing = one_time_tier.sponsors_listing
      recurring_tier_listing = recurring_tier.sponsors_listing
      sponsorship1 = create(:sponsorship, tier: one_time_tier)
      sponsor = sponsorship1.sponsor
      plan_subscription = sponsorship1.plan_subscription
      sponsorship2 = create(:sponsorship, sponsor: sponsor, tier: recurring_tier)
      assert_equal 2, plan_subscription.subscription_items.count,
        "should have a subscription item for each sponsorship"
      sponsor.clear_bulk_sponsorship_tier_ids
      service_start_date = "2022-09-22"
      service_end_date = "2022-10-21"
      invoiced_items = [
        Billing::Zuora::SubscribableInvoiceItem.new({
          "chargeId" => SecureRandom.alphanumeric(32),
          "unitPrice" => 5,
          "chargeName" => one_time_tier_listing.monthly_plan_or_charge_name,
          "chargeAmount" => 5.00,
          "quantity" => 1,
          "serviceStartDate" => service_start_date,
          "serviceEndDate" => service_end_date,
          "productRatePlanChargeId" => SecureRandom.alphanumeric(32),
        }, subscribable: one_time_tier),
        Billing::Zuora::SubscribableInvoiceItem.new({
          "chargeId" => SecureRandom.alphanumeric(32),
          "unitPrice" => 5,
          "chargeName" => recurring_tier_listing.monthly_plan_or_charge_name,
          "chargeAmount" => 5.00,
          "quantity" => 1,
          "serviceStartDate" => service_start_date,
          "serviceEndDate" => service_end_date,
          "productRatePlanChargeId" => SecureRandom.alphanumeric(32),
        }, subscribable: recurring_tier),
      ]
      billing_transaction = Billing::BillingTransaction.new(
        amount_in_cents: 10_00,
        plan_subscription: plan_subscription,
      )

      assert_hydro_message_difference("github.sponsors.v1.SponsorshipPaymentComplete", 2) do
        assert_difference("Billing::BillingTransaction::LineItem.count", 2) do
          billing_transaction.log_recurring_charge(
            billable_entity: sponsor,
            invoiced_items: invoiced_items,
            charge_type: "prorate-charge",
          )
        end
      end

      assert_equal 2, billing_transaction.reload.line_items.sponsorships.count
      assert_equal "prorate-charge", billing_transaction.transaction_type
      assert_equal 1, one_time_tier.reload.billing_transaction_line_items.count
      assert_equal 1, recurring_tier.reload.billing_transaction_line_items.count

      sponsors_line_item1 = billing_transaction.line_items.find_by(subscribable: one_time_tier)
      refute_nil sponsors_line_item1
      assert_equal 5_00, T.must(sponsors_line_item1).amount_in_cents
      assert_equal "#{one_time_tier_listing.name} - #{one_time_tier.name}", T.must(sponsors_line_item1).description
      assert_equal service_start_date, T.must(sponsors_line_item1).service_start_date.to_s
      assert_equal service_end_date, T.must(sponsors_line_item1).service_end_date.to_s

      sponsors_line_item2 = billing_transaction.line_items.find_by(subscribable: recurring_tier)
      refute_nil sponsors_line_item2
      assert_equal 5_00, T.must(sponsors_line_item2).amount_in_cents
      assert_equal "#{recurring_tier_listing.name} - #{recurring_tier.name}", T.must(sponsors_line_item2).description
      assert_equal service_start_date, T.must(sponsors_line_item2).service_start_date.to_s
      assert_equal service_end_date, T.must(sponsors_line_item2).service_end_date.to_s

      assert_hydro_published_partial({
        sponsorship: Hydro::EntitySerializer.sponsorship(sponsorship1),
        listing: Hydro::EntitySerializer.sponsors_listing(one_time_tier.sponsors_listing),
        tier: Hydro::EntitySerializer.sponsors_tier(one_time_tier),
        via_bulk_sponsorship: false,
      }, schema: "github.sponsors.v1.SponsorshipPaymentComplete")

      assert_hydro_published_partial({
        sponsorship: Hydro::EntitySerializer.sponsorship(sponsorship2),
        listing: Hydro::EntitySerializer.sponsors_listing(recurring_tier.sponsors_listing),
        tier: Hydro::EntitySerializer.sponsors_tier(recurring_tier),
        via_bulk_sponsorship: false,
      }, schema: "github.sponsors.v1.SponsorshipPaymentComplete")
    end

    test "creates separate line items for invoice items with a non-zero charge amount for the same subscribable but different rate plan charge IDs" do
      sub_item = create(:sponsors_subscription_item)
      user = sub_item.user
      plan_subscription = sub_item.plan_subscription
      published_tier = sub_item.subscribable
      listing = published_tier.sponsors_listing

      service_start_date = "2022-09-22"
      service_end_date = "2022-10-21"
      invoiced_items = [
        Billing::Zuora::SubscribableInvoiceItem.new({
          "unitPrice" => published_tier.monthly_price_in_dollars,
          "chargeName" => listing.monthly_plan_or_charge_name,
          "chargeAmount" => 12.11,
          "chargeId" => "flat_rate_plan_charge_id",
          "quantity" => 1,
          "serviceStartDate" => service_start_date,
          "serviceEndDate" => service_end_date,
          "productRatePlanChargeId" => SecureRandom.alphanumeric(32),
        }, subscribable: published_tier),
        Billing::Zuora::SubscribableInvoiceItem.new({
          "unitPrice" => published_tier.monthly_price_in_dollars,
          "chargeName" => SponsorsListing.fee_charge_name_for(listing.monthly_plan_or_charge_name),
          "chargeAmount" => 0.15,
          "chargeId" => "fee_rate_plan_charge_id",
          "quantity" => 1.0,
          "serviceStartDate" => service_start_date,
          "serviceEndDate" => service_end_date,
          "productRatePlanChargeId" => SecureRandom.alphanumeric(32),
        }, subscribable: published_tier),
      ]

      billing_transaction = Billing::BillingTransaction.new(
        amount_in_cents: 12_26,
        plan_subscription: plan_subscription,
      )

      # One line item is for the base cost of the sponsorship, the other is for the service fee:
      assert_difference "Billing::BillingTransaction::LineItem.count", 2 do
        billing_transaction.log_recurring_charge \
          billable_entity: user,
          invoiced_items: invoiced_items,
          charge_type: "prorate-charge"
      end
      billing_transaction.reload

      assert_equal 2, published_tier.reload.billing_transaction_line_items.count
      sponsors_line_items = billing_transaction.line_items
      assert_equal 2, sponsors_line_items.size
      sponsors_line_items.each do |line_item|
        assert_equal published_tier, line_item.subscribable
        assert_equal service_start_date, line_item.service_start_date.to_s
        assert_equal service_end_date, line_item.service_end_date.to_s
      end
      base_price_line_item = sponsors_line_items.detect { |li| li.amount_in_cents == 12_11 }
      refute_nil base_price_line_item
      fee_line_item = sponsors_line_items.detect { |li| li.amount_in_cents == 15 }
      refute_nil fee_line_item
      assert_equal "#{listing.name} - #{published_tier.name}", T.must(base_price_line_item).description
      assert_equal "#{listing.name} - #{published_tier.name} - fee", T.must(fee_line_item).description
      assert_equal "prorate-charge", billing_transaction.transaction_type
    end

    test "combines invoice items for the same subscribable when the rate plan charge ID is the same" do
      sub_item = create(:sponsors_subscription_item)
      user = sub_item.user
      plan_subscription = sub_item.plan_subscription
      published_tier = sub_item.subscribable
      listing = published_tier.sponsors_listing
      published_tier_product_rate_plan_charge_id = SecureRandom.alphanumeric(32)

      service_start_date = "2022-09-22"
      service_end_date = "2022-10-21"
      invoiced_items = [
        Billing::Zuora::InvoiceItem.new({
          "unitPrice" => 10,
          "chargeName" => "Not a matching charge name",
          "chargeId" => "foo",
          "chargeAmount" => 40.00,
          "quantity" => 1,
          "serviceStartDate" => service_start_date,
          "serviceEndDate" => service_end_date,
          "productRatePlanChargeId" => SecureRandom.alphanumeric(32),
        }),
        Billing::Zuora::SubscribableInvoiceItem.new({
          "unitPrice" => published_tier.monthly_price_in_cents / 100,
          "chargeName" => listing.monthly_plan_or_charge_name,
          "chargeId" => "flat_rate_plan_charge_id",
          "chargeAmount" => 12.11,
          "quantity" => 1,
          "serviceStartDate" => service_start_date,
          "serviceEndDate" => service_end_date,
          "productRatePlanChargeId" => published_tier_product_rate_plan_charge_id,
        }, subscribable: published_tier),
        Billing::Zuora::InvoiceItem.new({
          "unitPrice" => published_tier.monthly_price_in_cents / 100,
          "chargeName" => listing.monthly_plan_or_charge_name,
          "chargeId" => "flat_rate_plan_charge_id",
          "chargeAmount" => 7.89,
          "quantity" => 1,
          "serviceStartDate" => service_start_date,
          "serviceEndDate" => service_end_date,
          "productRatePlanChargeId" => published_tier_product_rate_plan_charge_id,
        })
      ]

      billing_transaction = Billing::BillingTransaction.new(
        amount_in_cents: 40_00,
        plan_subscription: plan_subscription,
      )

      assert_difference "Billing::BillingTransaction::LineItem.count", 2 do
        billing_transaction.log_recurring_charge \
          billable_entity: user,
          invoiced_items: invoiced_items,
          charge_type: "prorate-charge"
      end
      billing_transaction.reload

      assert_equal 1, published_tier.reload.billing_transaction_line_items.count
      assert_equal 1, billing_transaction.line_items.sponsorships.count
      # 20_00 is the sum of both Sponsors invoice items' charge_amounts in cents
      sponsors_line_item = billing_transaction.line_items.sponsorships.first
      assert_equal published_tier, T.must(sponsors_line_item).subscribable
      assert_equal 20_00, T.must(sponsors_line_item).amount_in_cents
      assert_equal "#{listing.name} - #{published_tier.name}", T.must(sponsors_line_item).description
      assert_equal "prorate-charge", billing_transaction.transaction_type
      assert_equal service_start_date, T.must(sponsors_line_item).service_start_date.to_s
      assert_equal service_end_date, T.must(sponsors_line_item).service_end_date.to_s
    end

    test "uses the subscribable for a matching SponsorsListing-based Zuora product subscription item" do
      sub_item = create(:sponsors_subscription_item)
      published_tier = sub_item.subscribable
      tier_price = published_tier.monthly_price_in_cents
      user = sub_item.user
      plan_subscription = sub_item.plan_subscription

      service_start_date = "2022-09-22"
      service_end_date = "2022-10-21"
      invoiced_items = [
        Billing::Zuora::SubscribableInvoiceItem.new({
          "chargeId" => SecureRandom.alphanumeric(32),
          "unitPrice" => tier_price / 100,
          "chargeName" => "Not a matching charge name",
          "chargeAmount" => tier_price / 100,
          "quantity" => 1,
          "serviceStartDate" => service_start_date,
          "serviceEndDate" => service_end_date,
          "productRatePlanChargeId" => SecureRandom.alphanumeric(32),
        }, subscribable: published_tier),
      ]

      billing_transaction = Billing::BillingTransaction.new(
        amount_in_cents: 10_00,
        plan_subscription: plan_subscription,
      )

      billing_transaction.log_recurring_charge \
        billable_entity: user,
        invoiced_items: invoiced_items,
        charge_type: "prorate-charge"
      billing_transaction.reload

      assert_equal 1, published_tier.reload.billing_transaction_line_items.count
      assert_equal 1, billing_transaction.line_items.sponsorships.count
      sponsors_line_item = billing_transaction.line_items.first
      assert_equal published_tier, T.must(sponsors_line_item).subscribable
      assert_equal tier_price, T.must(sponsors_line_item).amount_in_cents
      assert_equal published_tier.line_item_description, T.must(sponsors_line_item).description
      assert_equal "prorate-charge", billing_transaction.transaction_type
      assert_equal service_start_date, T.must(sponsors_line_item).service_start_date.to_s
      assert_equal service_end_date, T.must(sponsors_line_item).service_end_date.to_s
    end

    test "records metrics for sponsors invoice items" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      tier1 = create(:sponsors_tier, :approved_sponsors_listing)
      tier1_price = tier1.monthly_price_in_cents
      tier2 = create(:sponsors_tier, :approved_sponsors_listing)
      tier2_price = tier2.monthly_price_in_cents

      sub_item1 = create(
        :sponsors_subscription_item,
        subscribable: tier1,
      )
      user = sub_item1.user
      plan_subscription = sub_item1.plan_subscription
      create(
        :sponsors_subscription_item,
        subscribable: tier2,
      )

      invoiced_items = [
        Billing::Zuora::SubscribableInvoiceItem.new({
          "chargeId" => SecureRandom.alphanumeric(32),
          "unitPrice" => tier1_price / 100,
          "chargeName" => tier1.listing.monthly_plan_or_charge_name,
          "chargeAmount" => tier1_price / 100,
          "quantity" => 1.0,
          "serviceStartDate" => "2022-09-22",
          "serviceEndDate" => "2022-10-21",
          "productRatePlanChargeId" => SecureRandom.alphanumeric(32),
        }, subscribable: tier1),
        Billing::Zuora::InvoiceItem.new(
          "chargeId" => SecureRandom.alphanumeric(32),
          "unitPrice" => tier2_price / 100,
          "chargeName" => tier2.listing.monthly_plan_or_charge_name,
          "chargeAmount" => tier2_price / 100,
          "quantity" => 1.0,
          "serviceStartDate" => "2022-09-22",
          "serviceEndDate" => "2022-10-21",
          "productRatePlanChargeId" => SecureRandom.alphanumeric(32),
        )
      ]

      billing_transaction = Billing::BillingTransaction.new(
        amount_in_cents: tier1_price + tier2_price,
        plan_subscription: plan_subscription,
      )

      billing_transaction.log_recurring_charge \
        billable_entity: user,
        invoiced_items: invoiced_items,
        charge_type: "prorate-charge"

      refute_empty GitHub.dogstats.counts(
        "zuora.sponsors_invoice_item",
        tags: ["tracked:true", "transaction_type:prorate-charge"]
      )
      refute_empty GitHub.dogstats.counts(
        "zuora.sponsors_invoice_item",
        tags: ["tracked:false", "transaction_type:prorate-charge"]
      )
    end

    test "transitions Zuora subscription for users with untracked invoice items" do
      sub_item = create(
        :sponsors_subscription_item,
      )
      user = sub_item.user
      plan_subscription = sub_item.plan_subscription
      tier = sub_item.subscribable
      tier_price = tier.monthly_price_in_cents

      invoiced_items = [
        Billing::Zuora::InvoiceItem.new({
          "chargeId" => SecureRandom.alphanumeric(32),
          "unitPrice" => tier_price / 100,
          "chargeName" => tier.listing.monthly_plan_or_charge_name,
          "chargeAmount" => tier_price / 100,
          "quantity" => 1.0,
          "serviceStartDate" => "2022-09-22",
          "serviceEndDate" => "2022-10-21",
          "productRatePlanChargeId" => SecureRandom.alphanumeric(32),
        })
      ]

      billing_transaction = Billing::BillingTransaction.new(
        amount_in_cents: tier_price,
        plan_subscription: plan_subscription,
      )

      assert_enqueued_with(job: SynchronizePlanSubscriptionJob) do
        billing_transaction.log_recurring_charge \
          billable_entity: user,
          invoiced_items: invoiced_items,
          charge_type: "prorate-charge"
      end
    end

    test "updates sponsorship paid_at" do
      sponsorship = create(:sponsorship, tier: @sponsors_tier, paid_at: nil)
      sponsor = sponsorship.sponsor
      transaction = create(:billing_transaction, user: sponsor,
        amount_in_cents: @sponsors_tier.monthly_price_in_cents)

      freeze_time do
        transaction.log_recurring_charge(
          billable_entity: sponsor,
          invoiced_items: [
            Billing::Zuora::SubscribableInvoiceItem.new({
              "chargeId" => SecureRandom.alphanumeric(32),
              "unitPrice" => @sponsors_tier.monthly_price_in_dollars.to_i,
              "chargeName" => @sponsors_tier.listing.monthly_plan_or_charge_name,
              "chargeAmount" => @sponsors_tier.monthly_price_in_dollars,
              "quantity" => 1,
              "serviceStartDate" => Time.now.to_formatted_s(:date),
              "serviceEndDate" => (Time.now + 1.month).to_formatted_s(:date),
              "productRatePlanChargeId" => SecureRandom.alphanumeric(32),
            }, subscribable: @sponsors_tier),
          ]
        )

        assert_equal Time.now, sponsorship.reload.paid_at
      end
    end

    test "instruments payment complete audit log event for related sponsorship that started" do
      events = subscribe("sponsors.sponsor_sponsorship_payment_complete")
      sponsorship = create(:sponsorship, :unpaid, tier: @sponsors_tier)
      sponsor = sponsorship.sponsor
      transaction = create(:billing_transaction, user: sponsor,
        amount_in_cents: @sponsors_tier.monthly_price_in_cents)
      expected_payload = {
        active: true,
        public: true,
        frequency: "recurring",
        current_tier_id: @sponsors_tier.id,
        current_tier_monthly_amount_in_cents: @sponsors_tier.monthly_price_in_cents,
        sponsorable_user: @sponsors_tier.sponsorable.login,
        sponsorable_user_id: @sponsors_tier.sponsorable.id,
        sponsor: sponsor.login,
        sponsor_id: sponsorship.sponsor_id,
        sponsorship_id: sponsorship.id,
        actor: sponsor.login,
        actor_id: sponsorship.sponsor_id,
        user: sponsor.login,
        user_id: sponsorship.sponsor_id,
        first_payment: true,
        via_bulk_sponsorship: false,
        payment_source: "github",
      }

      assert_difference(-> { events.size }) do
        transaction.log_recurring_charge(
          billable_entity: sponsor,
          invoiced_items: [
            Billing::Zuora::SubscribableInvoiceItem.new({
              "chargeId" => SecureRandom.alphanumeric(32),
              "unitPrice" => @sponsors_tier.monthly_price_in_dollars.to_i,
              "chargeName" => @sponsors_tier.listing.monthly_plan_or_charge_name,
              "chargeAmount" => @sponsors_tier.monthly_price_in_dollars,
              "quantity" => 1,
              "serviceStartDate" => Time.now.to_formatted_s(:date),
              "serviceEndDate" => (Time.now + 1.month).to_formatted_s(:date),
              "productRatePlanChargeId" => SecureRandom.alphanumeric(32),
            }, subscribable: @sponsors_tier),
          ]
        )
      end

      refute_nil event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "instruments payment complete audit log for related sponsorship that did not just begin" do
      events = subscribe("sponsors.sponsor_sponsorship_payment_complete")
      sponsorship = travel_to(1.month.ago) { create(:sponsorship, tier: @sponsors_tier) }
      sponsor = sponsorship.sponsor
      transaction = travel_to(1.month.ago) do
        create(:billing_transaction, user: sponsor, amount_in_cents: @sponsors_tier.monthly_price_in_cents)
      end
      expected_payload = {
        active: true,
        public: true,
        frequency: "recurring",
        current_tier_id: @sponsors_tier.id,
        current_tier_monthly_amount_in_cents: @sponsors_tier.monthly_price_in_cents,
        sponsorable_user: @sponsors_tier.sponsorable.login,
        sponsorable_user_id: @sponsors_tier.sponsorable.id,
        sponsor: sponsor.login,
        sponsor_id: sponsorship.sponsor_id,
        sponsorship_id: sponsorship.id,
        actor: sponsor.login,
        actor_id: sponsorship.sponsor_id,
        user: sponsor.login,
        user_id: sponsorship.sponsor_id,
        first_payment: false,
        via_bulk_sponsorship: false,
        payment_source: "github",
      }

      # Previous line item for the sponsorship:
      travel_to(1.month.ago) do
        transaction.log_recurring_charge(
          billable_entity: sponsor,
          invoiced_items: [
            Billing::Zuora::SubscribableInvoiceItem.new({
              "chargeId" => SecureRandom.alphanumeric(32),
              "unitPrice" => @sponsors_tier.monthly_price_in_dollars.to_i,
              "chargeName" => @sponsors_tier.listing.monthly_plan_or_charge_name,
              "chargeAmount" => @sponsors_tier.monthly_price_in_dollars,
              "quantity" => 1,
              "serviceStartDate" => Time.now.to_formatted_s(:date),
              "serviceEndDate" => (Time.now + 1.month).to_formatted_s(:date),
              "productRatePlanChargeId" => SecureRandom.alphanumeric(32),
            }, subscribable: @sponsors_tier),
          ]
        )
      end

      assert_difference(-> { events.size }) do
        transaction.log_recurring_charge(
          billable_entity: sponsor,
          invoiced_items: [
            Billing::Zuora::SubscribableInvoiceItem.new({
              "chargeId" => SecureRandom.alphanumeric(32),
              "unitPrice" => @sponsors_tier.monthly_price_in_dollars.to_i,
              "chargeName" => @sponsors_tier.listing.monthly_plan_or_charge_name,
              "chargeAmount" => @sponsors_tier.monthly_price_in_dollars,
              "quantity" => 1,
              "serviceStartDate" => Time.now.to_formatted_s(:date),
              "serviceEndDate" => (Time.now + 1.month).to_formatted_s(:date),
              "productRatePlanChargeId" => SecureRandom.alphanumeric(32),
            }, subscribable: @sponsors_tier),
          ]
        )
      end

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "instruments payment complete Hydro event for related sponsorship that started" do
      freeze_time

      sponsorable_metadata = { "metadata_source" => "hacktoberfest" }
      sponsorship = create(:sponsorship, :unpaid, tier: @sponsors_tier, latest_sponsorable_metadata: sponsorable_metadata)
      sponsor = sponsorship.sponsor
      transaction = create(:billing_transaction, user: sponsor,
        amount_in_cents: @sponsors_tier.monthly_price_in_cents)

      expected_message = {
        request_context: nil,
        actor: Hydro::EntitySerializer.user(sponsor),
        sponsorship: Hydro::EntitySerializer.sponsorship(sponsorship),
        listing: Hydro::EntitySerializer.sponsors_listing(@sponsors_tier.sponsors_listing),
        tier: Hydro::EntitySerializer.sponsors_tier(@sponsors_tier),
        matchable: false,
        first_time_sponsor: true,
        first_payment: true,
        first_time_sponsorable: true,
        invoiced: false,
        completed_at: Time.current,
        payment_source: :GITHUB,
      }

      assert_hydro_message_difference("github.sponsors.v1.SponsorshipPaymentComplete") do
        transaction.log_recurring_charge(
          billable_entity: sponsor,
          invoiced_items: [
            Billing::Zuora::SubscribableInvoiceItem.new({
              "chargeId" => SecureRandom.alphanumeric(32),
              "unitPrice" => @sponsors_tier.monthly_price_in_dollars.to_i,
              "chargeName" => @sponsors_tier.listing.monthly_plan_or_charge_name,
              "chargeAmount" => @sponsors_tier.monthly_price_in_dollars,
              "quantity" => 1,
              "serviceStartDate" => Time.now.to_formatted_s(:date),
              "serviceEndDate" => (Time.now + 1.month).to_formatted_s(:date),
              "productRatePlanChargeId" => SecureRandom.alphanumeric(32),
            }, subscribable: @sponsors_tier),
          ]
        )
      end

      assert_hydro_messages(count: 1, schema: "github.sponsors.v1.SponsorshipPaymentComplete")
      assert_hydro_published(expected_message, schema: "github.sponsors.v1.SponsorshipPaymentComplete")
    end

    test "instruments payment complete Hydro event containing sponsorable metadata" do
      sponsorable_metadata = { "metadata_source" => "hacktoberfest" }
      sponsorship = create(:sponsorship, tier: @sponsors_tier, latest_sponsorable_metadata: sponsorable_metadata)
      sponsor = sponsorship.sponsor
      transaction = create(:billing_transaction, user: sponsor,
        amount_in_cents: @sponsors_tier.monthly_price_in_cents)

      assert_hydro_message_difference("github.sponsors.v1.SponsorshipPaymentComplete") do
        transaction.log_recurring_charge(
          billable_entity: sponsor,
          invoiced_items: [
            Billing::Zuora::SubscribableInvoiceItem.new({
              "chargeId" => SecureRandom.alphanumeric(32),
              "unitPrice" => @sponsors_tier.monthly_price_in_dollars.to_i,
              "chargeName" => @sponsors_tier.listing.monthly_plan_or_charge_name,
              "chargeAmount" => @sponsors_tier.monthly_price_in_dollars,
              "quantity" => 1,
              "serviceStartDate" => Time.now.to_formatted_s(:date),
              "serviceEndDate" => (Time.now + 1.month).to_formatted_s(:date),
              "productRatePlanChargeId" => SecureRandom.alphanumeric(32),
            }, subscribable: @sponsors_tier),
          ]
        )
      end

      assert_hydro_messages(count: 1, schema: "github.sponsors.v1.SponsorshipPaymentComplete")
      hydro_payload = hydro_messages(schema: "github.sponsors.v1.SponsorshipPaymentComplete").first
      assert_equal({ "source" => "hacktoberfest" }, hydro_payload[:sponsorship][:sponsorable_metadata])
    end if GitHub.sponsors_enabled?

    test "instruments payment complete for self-serve enterprise member orgs" do
      sub_item = create(:sponsors_subscription_item, :self_serve_business)
      listing = sub_item.listing
      tier = sub_item.sponsors_tier
      plan_subscription = sub_item.plan_subscription
      business = plan_subscription.billable_entity
      member_org = sub_item.organization

      sub_item2 = create(:sponsors_subscription_item,
        account: member_org,
      )

      other_member_org = create(:organization, business: business)
      other_member_org_sub_item = create(:sponsors_subscription_item,
        account: other_member_org,
        subscribable: tier,
      )

      sponsorship = create(:sponsorship, :unpaid,
        sponsor: member_org,
        tier: tier,
        subscription_item: sub_item,
      )
      sponsorship2 = create(:sponsorship, :unpaid,
        sponsor: member_org,
        tier: sub_item2.subscribable,
        subscription_item: sub_item2,
      )
      other_member_org_sponsorship = create(:sponsorship, :unpaid,
        sponsor: other_member_org,
        tier: tier,
        subscription_item: other_member_org_sub_item,
      )
      transaction = create(:billing_transaction, :business_owned,
        plan_subscription: plan_subscription,
        amount_in_cents: tier.monthly_price_in_cents * 2 + sub_item2.monthly_price_in_cents
      )

      transaction.log_recurring_charge(
        billable_entity: business,
        invoiced_items: [
          Billing::Zuora::SubscribableInvoiceItem.new({
            "chargeId" => SecureRandom.alphanumeric(32),
            "chargeName" => listing.monthly_plan_or_charge_name,
            "chargeAmount" => tier.monthly_price_in_dollars,
            "quantity" => 1,
            "serviceStartDate" => Time.now.to_formatted_s(:date),
            "serviceEndDate" => (Time.now + 1.month).to_formatted_s(:date),
            "productRatePlanChargeId" => SecureRandom.alphanumeric(32),
          }, subscription_item: sub_item),
          Billing::Zuora::SubscribableInvoiceItem.new({
            "chargeId" => SecureRandom.alphanumeric(32),
            "chargeName" => sub_item2.listing.monthly_plan_or_charge_name,
            "chargeAmount" => sub_item2.subscribable.monthly_price_in_dollars,
            "quantity" => 1,
            "serviceStartDate" => Time.now.to_formatted_s(:date),
            "serviceEndDate" => (Time.now + 1.month).to_formatted_s(:date),
            "productRatePlanChargeId" => SecureRandom.alphanumeric(32),
          }, subscription_item: sub_item2),
          Billing::Zuora::SubscribableInvoiceItem.new({
            "chargeId" => SecureRandom.alphanumeric(32),
            "chargeName" => listing.monthly_plan_or_charge_name,
            "chargeAmount" => tier.monthly_price_in_dollars,
            "quantity" => 1,
            "serviceStartDate" => Time.now.to_formatted_s(:date),
            "serviceEndDate" => (Time.now + 1.month).to_formatted_s(:date),
            "productRatePlanChargeId" => SecureRandom.alphanumeric(32),
          }, subscription_item: other_member_org_sub_item),
        ]
      )

      hydro_payloads = hydro_messages(schema: "github.sponsors.v1.SponsorshipPaymentComplete")
      assert_equal 3, hydro_payloads.count
    end if GitHub.sponsors_enabled?

    test "instruments payment complete Hydro event for related sponsorship that did not just begin" do
      freeze_time

      sponsorship = travel_to(1.month.ago) { create(:sponsorship, tier: @sponsors_tier) }
      sponsor = sponsorship.sponsor
      transaction = travel_to(1.month.ago) do
        create(:billing_transaction, user: sponsor, amount_in_cents: @sponsors_tier.monthly_price_in_cents)
      end
      message = {
        request_context: nil,
        actor: Hydro::EntitySerializer.user(sponsor),
        sponsorship: Hydro::EntitySerializer.sponsorship(sponsorship),
        listing: Hydro::EntitySerializer.sponsors_listing(@sponsors_tier.sponsors_listing),
        tier: Hydro::EntitySerializer.sponsors_tier(@sponsors_tier),
        matchable: false,
        first_time_sponsor: true,
        first_payment: false,
        first_time_sponsorable: true,
        invoiced: false,
        completed_at: Time.current,
        payment_source: :GITHUB,
      }

      # Previous line item for the sponsorship:
      travel_to(1.month.ago) do
        transaction.log_recurring_charge(
          billable_entity: sponsor,
          invoiced_items: [
            Billing::Zuora::SubscribableInvoiceItem.new({
              "chargeId" => SecureRandom.alphanumeric(32),
              "unitPrice" => @sponsors_tier.monthly_price_in_dollars.to_i,
              "chargeName" => @sponsors_tier.listing.monthly_plan_or_charge_name,
              "chargeAmount" => @sponsors_tier.monthly_price_in_dollars,
              "quantity" => 1,
              "serviceStartDate" => Time.now.to_formatted_s(:date),
              "serviceEndDate" => (Time.now + 1.month).to_formatted_s(:date),
              "productRatePlanChargeId" => SecureRandom.alphanumeric(32),
            }, subscribable: @sponsors_tier),
          ]
        )
      end

      reset_hydro

      assert_hydro_message_difference("github.sponsors.v1.SponsorshipPaymentComplete") do
        transaction.log_recurring_charge(
          billable_entity: sponsor,
          invoiced_items: [
            Billing::Zuora::SubscribableInvoiceItem.new({
              "chargeId" => SecureRandom.alphanumeric(32),
              "unitPrice" => @sponsors_tier.monthly_price_in_dollars.to_i,
              "chargeName" => @sponsors_tier.listing.monthly_plan_or_charge_name,
              "chargeAmount" => @sponsors_tier.monthly_price_in_dollars,
              "quantity" => 1,
              "serviceStartDate" => Time.now.to_formatted_s(:date),
              "serviceEndDate" => (Time.now + 1.month).to_formatted_s(:date),
              "productRatePlanChargeId" => SecureRandom.alphanumeric(32),
            }, subscribable: @sponsors_tier),
          ]
        )
      end
      assert_hydro_published(message, schema: "github.sponsors.v1.SponsorshipPaymentComplete")
    end if GitHub.sponsors_enabled?

    test "instruments payment complete audit log for concurrent one-time payment" do
      sponsorship = travel_to(1.month.ago) { create(:sponsorship, tier: @sponsors_tier) }
      sponsor = sponsorship.sponsor
      initial_transaction = travel_to(1.month.ago) do
        create(:billing_transaction, user: sponsor, amount_in_cents: @sponsors_tier.monthly_price_in_cents)
      end
      travel_to(1.month.ago) do
        initial_transaction.log_recurring_charge(
          billable_entity: sponsor,
          invoiced_items: [
            Billing::Zuora::SubscribableInvoiceItem.new({
              "chargeId" => SecureRandom.alphanumeric(32),
              "unitPrice" => @sponsors_tier.monthly_price_in_dollars.to_i,
              "chargeName" => @sponsors_tier.listing.monthly_plan_or_charge_name,
              "chargeAmount" => @sponsors_tier.monthly_price_in_dollars,
              "quantity" => 1,
              "serviceStartDate" => Time.now.to_formatted_s(:date),
              "serviceEndDate" => (Time.now + 1.month).to_formatted_s(:date),
              "productRatePlanChargeId" => SecureRandom.alphanumeric(32),
            }, subscribable: @sponsors_tier),
          ]
        )
      end
      one_time_tier = create(:sponsors_tier, :one_time, :published,
        sponsors_listing: @sponsors_tier.sponsors_listing
      )
      concurrent_transaction = create(:billing_transaction,
        user: sponsorship.sponsor,
        amount_in_cents: one_time_tier.monthly_price_in_cents
      )

      events = assert_performed_audit_entries(count: 1, only: "sponsors.sponsor_sponsorship_payment_complete") do
        concurrent_transaction.log_recurring_charge(
          billable_entity: sponsor,
          invoiced_items: [
            Billing::Zuora::SubscribableInvoiceItem.new({
              "chargeId" => SecureRandom.alphanumeric(32),
              "unitPrice" => one_time_tier.monthly_price_in_dollars.to_i,
              "chargeName" => one_time_tier.listing.monthly_plan_or_charge_name,
              "chargeAmount" => one_time_tier.monthly_price_in_dollars,
              "quantity" => 1,
              "serviceStartDate" => Time.now.to_formatted_s(:date),
              "serviceEndDate" => (Time.now + 1.month).to_formatted_s(:date),
              "productRatePlanChargeId" => SecureRandom.alphanumeric(32),
            }, subscribable: one_time_tier),
          ]
        )
      end

      expected_payload = {
        frequency: "one_time",
        current_tier_monthly_amount_in_cents: one_time_tier.monthly_price_in_cents,
      }

      assert_subset_hash expected_payload, events.first
    end

    test "instruments payment complete Hydro event for concurrent one-time payment" do
      freeze_time

      sponsorship = travel_to(1.month.ago) { create(:sponsorship, tier: @sponsors_tier) }
      sponsor = sponsorship.sponsor
      initial_transaction = travel_to(1.month.ago) do
        create(:billing_transaction, user: sponsor, amount_in_cents: @sponsors_tier.monthly_price_in_cents)
      end
      travel_to(1.month.ago) do
        initial_transaction.log_recurring_charge(
          billable_entity: sponsor,
          invoiced_items: [
            Billing::Zuora::SubscribableInvoiceItem.new({
              "chargeId" => SecureRandom.alphanumeric(32),
              "unitPrice" => @sponsors_tier.monthly_price_in_dollars.to_i,
              "chargeName" => @sponsors_tier.listing.monthly_plan_or_charge_name,
              "chargeAmount" => @sponsors_tier.monthly_price_in_dollars,
              "quantity" => 1,
              "serviceStartDate" => Time.now.to_formatted_s(:date),
              "serviceEndDate" => (Time.now + 1.month).to_formatted_s(:date),
              "productRatePlanChargeId" => SecureRandom.alphanumeric(32),
            }, subscribable: @sponsors_tier),
          ]
        )
      end
      one_time_tier = create(:sponsors_tier, :one_time, :published,
        sponsors_listing: @sponsors_tier.sponsors_listing
      )
      concurrent_transaction = create(:billing_transaction, user: sponsor,
        amount_in_cents: one_time_tier.monthly_price_in_cents)

      reset_hydro

      assert_hydro_message_difference("github.sponsors.v1.SponsorshipPaymentComplete") do
        concurrent_transaction.log_recurring_charge(
          billable_entity: sponsor,
          invoiced_items: [
            Billing::Zuora::SubscribableInvoiceItem.new({
              "chargeId" => SecureRandom.alphanumeric(32),
              "unitPrice" => one_time_tier.monthly_price_in_dollars.to_i,
              "chargeName" => one_time_tier.listing.monthly_plan_or_charge_name,
              "chargeAmount" => one_time_tier.monthly_price_in_dollars,
              "quantity" => 1,
              "serviceStartDate" => Time.now.to_formatted_s(:date),
              "serviceEndDate" => (Time.now + 1.month).to_formatted_s(:date),
              "productRatePlanChargeId" => SecureRandom.alphanumeric(32),
            }, subscribable: one_time_tier),
          ]
        )
      end

      expected_message = {
        request_context: nil,
        actor: Hydro::EntitySerializer.user(sponsor),
        sponsorship: Hydro::EntitySerializer.sponsorship(sponsorship),
        listing: Hydro::EntitySerializer.sponsors_listing(one_time_tier.sponsors_listing),
        tier: Hydro::EntitySerializer.sponsors_tier(one_time_tier),
        matchable: false,
        first_time_sponsor: true,
        first_payment: true,
        first_time_sponsorable: true,
        completed_at: Time.current,
        payment_source: :GITHUB,
      }

      assert_hydro_published(expected_message, schema: "github.sponsors.v1.SponsorshipPaymentComplete")
    end if GitHub.sponsors_enabled?

    test "launches a low credit balance warning job for sponsors-invoiced user's recurring sponsorship payment" do
      sponsors_invoiced_org = create(:credit_card_org, :sponsors_invoiced, :with_sponsors_invoiced_plan_subscription)
      sponsorship = create(:sponsorship, sponsor: sponsors_invoiced_org, tier: @sponsors_tier)
      Billing::Zuora::Account.any_instance.stubs(:credit_balance).returns(sponsorship.amount)
      zero_balance_date = sponsors_invoiced_org.sponsors_zero_balance_date
      refute_nil zero_balance_date, "need to know the date their sponsorship balance will hit $0 before we can " \
        "send the mail via the job"

      invoiced_items = [
        Billing::Zuora::SubscribableInvoiceItem.new({
          "chargeId" => SecureRandom.alphanumeric(32),
          "unitPrice" => @sponsors_tier.monthly_price_in_dollars.to_i,
          "chargeName" => @sponsors_tier.listing.monthly_plan_or_charge_name,
          "chargeAmount" => @sponsors_tier.monthly_price_in_dollars,
          "quantity" => 1,
          "serviceStartDate" => Time.now.to_formatted_s(:date),
          "serviceEndDate" => (Time.now + 1.month).to_formatted_s(:date),
          "productRatePlanChargeId" => SecureRandom.alphanumeric(32),
        }, subscribable: @sponsors_tier),
      ]

      billing_transaction = Billing::BillingTransaction.new(
        amount_in_cents: @sponsors_tier.monthly_price_in_cents.to_i,
        plan_subscription: sponsors_invoiced_org.sponsors_plan_subscription,
      )

      assert_enqueued_with(
        job: SponsorsLowCreditBalanceWarningJob,
        args: [
          {
            sponsor: sponsors_invoiced_org,
            zero_balance_date: zero_balance_date,
          }
        ]
      ) do
        billing_transaction.log_recurring_charge(
          billable_entity: sponsors_invoiced_org,
          invoiced_items: invoiced_items,
          charge_type: "prorate-charge",
        )
      end
    end

    # see https://github.com/github/sponsors/issues/4543
    test "does not launch a low credit balance warning job for Sponsors-invoiced user without recurring sponsorship" do
      sponsors_invoiced_org = create(:credit_card_org, :sponsors_invoiced, :with_sponsors_invoiced_plan_subscription)
      create(:billing_plan_subscription, :zuora, user: sponsors_invoiced_org)
      one_time_tier = create(:sponsors_tier, :one_time, :approved_sponsors_listing)

      charge_amount = Billing::Money.new(100_00)
      billing_transaction = Billing::BillingTransaction.new(
        amount_in_cents: charge_amount.cents,
        plan_subscription: sponsors_invoiced_org.plan_subscription,
      )

      invoiced_items = [
        # non-Sponsors charge
        Billing::Zuora::InvoiceItem.new({
          "chargeId" => SecureRandom.alphanumeric(32),
          "id" => "invoice-id",
          "chargeName" => "charge-name",
          "chargeAmount" => charge_amount.dollars,
          "quantity" => 1.0,
          "serviceStartDate" => GitHub::Billing.today.to_formatted_s(:date),
          "serviceEndDate" => (GitHub::Billing.today + 1.week).to_formatted_s(:date),
          "productRatePlanChargeId" => SecureRandom.alphanumeric(32),
        }),
        # one-time Sponsors charge
        Billing::Zuora::SubscribableInvoiceItem.new({
          "chargeId" => SecureRandom.alphanumeric(32),
          "unitPrice" => one_time_tier.monthly_price_in_dollars.to_i,
          "chargeName" => one_time_tier.listing.monthly_plan_or_charge_name,
          "chargeAmount" => one_time_tier.monthly_price_in_dollars,
          "quantity" => 1,
          "serviceStartDate" => GitHub::Billing.today.to_formatted_s(:date),
          "serviceEndDate" => GitHub::Billing.today.to_formatted_s(:date),
          "productRatePlanChargeId" => SecureRandom.alphanumeric(32),
        }, subscribable: one_time_tier),
      ]

      assert_enqueued_jobs 0, only: SponsorsLowCreditBalanceWarningJob do
        billing_transaction.log_recurring_charge(
          billable_entity: sponsors_invoiced_org,
          invoiced_items: invoiced_items,
          charge_type: "prorate-charge",
        )
      end
    end

    test "does not launch a low credit balance warning job for non-Sponsors-invoiced org" do
      credit_card_org = create(:credit_card_org)
      create(:billing_plan_subscription, :zuora, user: credit_card_org)

      invoiced_items = [
        Billing::Zuora::SubscribableInvoiceItem.new({
          "chargeId" => SecureRandom.alphanumeric(32),
          "unitPrice" => @sponsors_tier.monthly_price_in_dollars.to_i,
          "chargeName" => @sponsors_tier.listing.monthly_plan_or_charge_name,
          "chargeAmount" => @sponsors_tier.monthly_price_in_dollars,
          "quantity" => 1,
          "serviceStartDate" => Time.now.to_formatted_s(:date),
          "serviceEndDate" => (Time.now + 1.month).to_formatted_s(:date),
          "productRatePlanChargeId" => SecureRandom.alphanumeric(32),
        }, subscribable: @sponsors_tier),
      ]

      billing_transaction = Billing::BillingTransaction.new(
        amount_in_cents: @sponsors_tier.monthly_price_in_cents.to_i,
        plan_subscription: credit_card_org.plan_subscription,
      )

      assert_enqueued_jobs 0, only: SponsorsLowCreditBalanceWarningJob do
        billing_transaction.log_recurring_charge(
          billable_entity: credit_card_org,
          invoiced_items: invoiced_items,
          charge_type: "prorate-charge",
        )
      end
    end
  end

  context "for_sponsors_plan_subscription scope" do
    test "returns billing transactions for a given sponsors plan subscription" do
      org = create(:invoiced_organization, :sponsors_invoiced, :with_sponsors_invoiced_plan_subscription)
      sponsors_plan_subscription = org.sponsors_plan_subscription
      transaction = create(:billing_transaction, plan_subscription: sponsors_plan_subscription)

      result = Billing::BillingTransaction.for_sponsors_plan_subscription(sponsors_plan_subscription.id)

      assert_equal [transaction], result
    end
  end

  context "#zuora_payment_gateway" do
    test "returns Sponsors Stripe v2 when using a credit card to pay for sponsorships and feature is enabled" do
      sponsors_plan_sub = create(:billing_plan_subscription, purpose: :sponsors, customer: @user.customer,
        user: @user)
      transaction = create(:billing_transaction, payment_type: :credit_card, plan_subscription: sponsors_plan_sub,
        user: @user)
      assert_equal Billing::Zuora::PaymentGateway::SPONSORS_STRIPE_V2, transaction.zuora_payment_gateway
    end

    test "returns Paypal when using Paypal to pay for sponsorships and feature is enabled" do
      sponsors_plan_sub = create(:billing_plan_subscription, purpose: :sponsors, customer: @user.customer,
        user: @user)
      transaction = create(:billing_transaction, payment_type: :paypal, plan_subscription: sponsors_plan_sub,
        user: @user)
      assert_equal Billing::Zuora::PaymentGateway::PAYPAL, transaction.zuora_payment_gateway
    end
  end
end
