# typed: true
# frozen_string_literal: true

require "test_helper"

class MarketplaceListingInsightTest < GitHub::TestCase
  fixtures do
    @listing = create(:marketplace_listing)
    @free_plan = create(:marketplace_listing_plan, :free, listing: @listing)
    @paid_plan = create(:marketplace_listing_plan, :free_trial, listing: @listing, has_free_trial: true)

    end_date = Date.parse("2017-12-01")
    46.times do |i|
      record_date = end_date - i.days
      create(:marketplace_listing_insight, listing: @listing, recorded_on: record_date)
    end
  end

  setup do
    GitHub.stubs(:presto).returns(stub(run: [[], [[84, 42]]]))
  end

  context "time period" do
    test "current day" do
      insights = Timecop.freeze("2017-12-01") { Marketplace::ListingInsight.for_period(:day) }

      assert_equal 1, insights.size
      assert_equal Date.parse("2017-11-29"), insights[0].recorded_on
    end

    test "past day" do
      past_day = Date.parse("2017-11-15")
      insights = Timecop.freeze("2017-12-01") { Marketplace::ListingInsight.for_period(:day, past_day) }

      assert_equal 1, insights.size
      assert_equal Date.parse("2017-11-15"), insights[0].recorded_on
    end

    test "current week" do
      insights = Timecop.freeze("2017-12-01") { Marketplace::ListingInsight.for_period(:week) }

      assert_equal 7, insights.size
      assert_equal Date.parse("2017-11-23"), insights[0].recorded_on
      assert_equal Date.parse("2017-11-29"), insights[6].recorded_on
    end

    test "past week" do
      past_day = Date.parse("2017-11-15")
      insights = Timecop.freeze("2017-12-01") { Marketplace::ListingInsight.for_period(:week, past_day) }

      assert_equal 7, insights.size
      assert_equal Date.parse("2017-11-09"), insights[0].recorded_on
      assert_equal Date.parse("2017-11-15"), insights[6].recorded_on
    end

    test "current month" do
      insights = Timecop.freeze("2017-12-01") { Marketplace::ListingInsight.for_period(:month) }

      assert_equal 30, insights.size
      assert_equal Date.parse("2017-10-31"), insights[0].recorded_on
      assert_equal Date.parse("2017-11-29"), insights[29].recorded_on
    end

    test "past month" do
      past_day = Date.parse("2017-11-15")
      insights = Timecop.freeze("2017-12-01") { Marketplace::ListingInsight.for_period(:month, past_day) }

      assert_equal 30, insights.size
      assert_equal Date.parse("2017-10-17"), insights[0].recorded_on
      assert_equal Date.parse("2017-11-15"), insights[29].recorded_on
    end

    test "past month will not return incomplete metrics regardless of end_date being set" do
      past_day = Date.parse("2017-12-01")
      insights = Timecop.freeze("2017-12-01") { Marketplace::ListingInsight.for_period(:month, past_day) }

      assert_equal 30, insights.size
      assert_equal Date.parse("2017-10-31"), insights[0].recorded_on
      assert_equal Date.parse("2017-11-29"), insights[29].recorded_on
    end

    test "alltime" do
      insights = Timecop.freeze("2017-12-03") { Marketplace::ListingInsight.for_period(:alltime).to_a }

      assert_equal 3, insights.size
      assert_equal "2017-10", insights[0].recorded_on.strftime("%Y-%m")
      assert_equal "2017-11", insights[1].recorded_on.strftime("%Y-%m")
      assert_equal "2017-12", insights[2].recorded_on.strftime("%Y-%m")
    end

    test "alltime will not include incomplete metrics" do
      # Metrics are fully synced after 2 days. Since there is no fully synced data in December, we do not return it.
      insights = Timecop.freeze("2017-12-02") { Marketplace::ListingInsight.for_period(:alltime).to_a }

      assert_equal 2, insights.size
      assert_equal "2017-10", insights[0].recorded_on.strftime("%Y-%m")
      assert_equal "2017-11", insights[1].recorded_on.strftime("%Y-%m")
    end
  end

  test "alltime sums by month" do
    insights = Timecop.freeze("2017-12-03") { Marketplace::ListingInsight.for_period(:alltime).to_a }

    # October and December are partial months, November is a full month.
    default_insight = build(:marketplace_listing_insight, listing: @listing)
    Marketplace::ListingInsight::SUMMABLE_COLUMNS.each do |col|
      assert_equal default_insight.send(col) * 30, insights[1].send(col)
    end
  end

  context "updating transaction metrics" do
    test "records zeroes when no transactions exist" do
      assert_nil Marketplace::ListingInsight.find_by(marketplace_listing_id: @listing.id, recorded_on: yesterday)

      insight = Marketplace::ListingInsight.new(listing: @listing, recorded_on: yesterday)
      insight.update_metrics!

      assert recorded = Marketplace::ListingInsight.find_by(marketplace_listing_id: @listing.id, recorded_on: yesterday)
      recorded = T.must(recorded)
      assert_equal 0, recorded.new_purchases
      assert_equal 0, recorded.new_free_subscriptions
      assert_equal 0, recorded.new_paid_subscriptions
      assert_equal 0, recorded.new_free_trial_subscriptions
      assert_equal 0, recorded.new_seats
      assert_equal 0, recorded.upgrades
      assert_equal 0, recorded.upgraded_seats
      assert_equal 0, recorded.downgrades
      assert_equal 0, recorded.downgraded_seats
      assert_equal 0, recorded.cancellations
      assert_equal 0, recorded.cancelled_seats
      assert_equal 0, recorded.mrr_gained
      assert_equal 0, recorded.mrr_lost
      assert_equal 0, recorded.mrr_recurring
    end

    test "creates a new record" do
      transactions = []
      transactions << create(:transaction, :mp_purchased, current_subscribable: @paid_plan)
      transactions << create(:transaction, :mp_purchased, current_subscribable: @paid_plan)
      transactions << create(:transaction, :mp_purchased, current_subscribable: @free_plan)
      transactions << create(:transaction, :mp_cancelled, old_subscribable: @paid_plan)
      transactions << create(:transaction, :mp_changed, old_subscribable: @free_plan, current_subscribable: @paid_plan)
      transactions << create(:transaction, :mp_changed, old_subscribable: @paid_plan, current_subscribable: @free_plan)
      Transaction.where(id: transactions.map(&:id)).update_all(timestamp: yesterday_timestamp)

      # For mrr_recurring
      line_items = [:settled, :settled, :submitted_for_settlement].map do |status|
        create(:billing_transaction_line_item,
          billing_transaction: create(:billing_transaction, last_status: status, transaction_type: "recurring-charge"),
          subscribable: @paid_plan,
          quantity: 1,
          amount_in_cents: @paid_plan.monthly_price_in_cents,
        )
      end

      # For mrr_gained
      line_items += [:settled, :submitted_for_settlement].map do |status|
        create(:billing_transaction_line_item,
          billing_transaction: create(:billing_transaction, last_status: status, transaction_type: "prorate-charge"),
          subscribable: @paid_plan,
          quantity: 1,
          amount_in_cents: @paid_plan.monthly_price_in_cents,
        )
      end

      # Make sure line items from other listings aren't included
      other_listing = create(:marketplace_listing, :verified)
      other_plan = create(:marketplace_listing_plan, listing: other_listing, monthly_price_in_cents: 4200)
      line_items += %w(prorate-charge recurring-charge).map do |transaction_type|
        create(:billing_transaction_line_item,
          billing_transaction: create(:billing_transaction, last_status: :settled, transaction_type: transaction_type),
          subscribable: other_plan,
          quantity: 1,
          amount_in_cents: other_plan.monthly_price_in_cents,
        )
      end

      Billing::BillingTransaction::LineItem.where(id: line_items.map(&:id)).update_all(created_at: yesterday_timestamp)

      assert_nil Marketplace::ListingInsight.find_by(marketplace_listing_id: @listing.id, recorded_on: yesterday)

      insight = Marketplace::ListingInsight.new(listing: @listing, recorded_on: yesterday)
      insight.update_metrics!

      assert recorded = Marketplace::ListingInsight.find_by(marketplace_listing_id: @listing.id, recorded_on: yesterday)
      recorded = T.must(recorded)
      assert_equal 3, recorded.new_purchases
      assert_equal 1, recorded.new_free_subscriptions
      assert_equal 2, recorded.new_paid_subscriptions
      assert_equal 2, recorded.new_free_trial_subscriptions
      assert_equal 3, recorded.new_seats
      assert_equal 1, recorded.upgrades
      assert_equal 1, recorded.upgraded_seats
      assert_equal 1, recorded.downgrades
      assert_equal 1, recorded.downgraded_seats
      assert_equal 1, recorded.cancellations
      assert_equal 1, recorded.cancelled_seats
      assert_equal @paid_plan.monthly_price_in_cents * 2, recorded.mrr_gained
      assert_equal @paid_plan.monthly_price_in_cents * 2, recorded.mrr_lost
      assert_equal @paid_plan.monthly_price_in_cents * 2, recorded.mrr_recurring
    end

    test "updates an existing record" do
      create(:marketplace_listing_insight, listing: @listing, recorded_on: yesterday)

      transactions = []
      transactions << create(:transaction, :mp_purchased, current_subscribable: @paid_plan)
      transactions << create(:transaction, :mp_purchased, current_subscribable: @paid_plan)
      transactions << create(:transaction, :mp_purchased, current_subscribable: @free_plan)
      transactions << create(:transaction, :mp_cancelled, old_subscribable: @paid_plan)
      transactions << create(:transaction, :mp_changed, old_subscribable: @free_plan, current_subscribable: @paid_plan)
      transactions << create(:transaction, :mp_changed, old_subscribable: @paid_plan, current_subscribable: @free_plan)
      Transaction.where(id: transactions.map(&:id)).update_all(timestamp: yesterday_timestamp)

      # For mrr_recurring
      line_items = [:settled, :settled, :submitted_for_settlement].map do |status|
        create(:billing_transaction_line_item,
          billing_transaction: create(:billing_transaction, last_status: status, transaction_type: "recurring-charge"),
          subscribable: @paid_plan,
          quantity: 1,
          amount_in_cents: @paid_plan.monthly_price_in_cents,
        )
      end

      # For mrr_gained
      line_items += [:settled, :submitted_for_settlement].map do |status|
        create(:billing_transaction_line_item,
          billing_transaction: create(:billing_transaction, last_status: status, transaction_type: "prorate-charge"),
          subscribable: @paid_plan,
          quantity: 1,
          amount_in_cents: @paid_plan.monthly_price_in_cents,
        )
      end

      # Make sure line items from other listings aren't included
      other_listing = create(:marketplace_listing, :verified)
      other_plan = create(:marketplace_listing_plan, listing: other_listing, monthly_price_in_cents: 4200)
      line_items += %w(prorate-charge recurring-charge).map do |transaction_type|
        create(:billing_transaction_line_item,
          billing_transaction: create(:billing_transaction, last_status: :settled, transaction_type: transaction_type),
          subscribable: other_plan,
          quantity: 1,
          amount_in_cents: other_plan.monthly_price_in_cents,
        )
      end

      Billing::BillingTransaction::LineItem.where(id: line_items.map(&:id)).update_all(created_at: yesterday_timestamp)

      refute_nil Marketplace::ListingInsight.find_by(marketplace_listing_id: @listing.id, recorded_on: yesterday)

      insight = Marketplace::ListingInsight.new(listing: @listing, recorded_on: yesterday)
      insight.update_metrics!

      assert updated = Marketplace::ListingInsight.find_by(marketplace_listing_id: @listing.id, recorded_on: yesterday)
      updated = T.must(updated)
      assert_equal 3, updated.new_purchases
      assert_equal 1, updated.new_free_subscriptions
      assert_equal 2, updated.new_paid_subscriptions
      assert_equal 2, updated.new_free_trial_subscriptions
      assert_equal 3, updated.new_seats
      assert_equal 1, updated.upgrades
      assert_equal 1, updated.upgraded_seats
      assert_equal 1, updated.downgrades
      assert_equal 1, updated.downgraded_seats
      assert_equal 1, updated.cancellations
      assert_equal 1, updated.cancelled_seats
      assert_equal @paid_plan.monthly_price_in_cents * 2, updated.mrr_gained
      assert_equal @paid_plan.monthly_price_in_cents * 2, updated.mrr_lost
      assert_equal @paid_plan.monthly_price_in_cents * 2, updated.mrr_recurring
    end

    test "can update only transaction metrics" do
      transaction = create(:transaction, :mp_purchased, current_subscribable: @paid_plan)
      transaction.update_column(:timestamp, yesterday_timestamp)
      install = create(:oauth_authorization, application: @listing.listable)
      install.update_attribute(:created_at, yesterday_timestamp)

      insight = Marketplace::ListingInsight.new(listing: @listing, recorded_on: yesterday)
      insight.update_metrics!(:transaction)

      assert recorded = Marketplace::ListingInsight.find_by(marketplace_listing_id: @listing.id, recorded_on: yesterday)
      recorded = T.must(recorded)
      assert_equal 1, recorded.new_purchases
      assert_equal 0, recorded.installs
      assert_equal 0, recorded.pageviews
    end

    test "free trial conversions includes automated billing after trial" do
      subscription = create(:billing_subscription_item,
        subscribable: @paid_plan,
        free_trial_ends_on: yesterday,
      )
      auto_conversion = create(:transaction,
        :mp_changed,
        user: subscription.plan_subscription.user,
        current_subscribable: @paid_plan,
        current_subscribable_quantity: 1,
        old_subscribable: @paid_plan,
        old_subscribable_quantity: 1,
      )
      auto_conversion.update_column(:timestamp, yesterday_timestamp)

      insight = Marketplace::ListingInsight.new(listing: @listing, recorded_on: yesterday)
      insight.update_metrics!

      assert updated = Marketplace::ListingInsight.find_by(marketplace_listing_id: @listing.id, recorded_on: yesterday)
      assert_equal 1, T.must(updated).free_trial_conversions
    end

    test "free trial conversions includes manual upgrades during trial" do
      more_expensive_plan = create(:marketplace_listing_plan, listing: @listing, monthly_price_in_cents: @paid_plan.monthly_price_in_cents + 100)

      trial_subscription = create(:billing_subscription_item,
        :cancelled,
        subscribable: @paid_plan,
        free_trial_ends_on: yesterday + 1.week,
      )
      manual_conversion = create(:transaction,
        :mp_changed,
        user: trial_subscription.plan_subscription.user,
        current_subscribable: more_expensive_plan,
        current_subscribable_quantity: 1,
        old_subscribable: @paid_plan,
        old_subscribable_quantity: 1,
      )
      manual_conversion.update_column(:timestamp, yesterday_timestamp)

      insight = Marketplace::ListingInsight.new(listing: @listing, recorded_on: yesterday)
      insight.update_metrics!

      assert updated = Marketplace::ListingInsight.find_by(marketplace_listing_id: @listing.id, recorded_on: yesterday)
      assert_equal 1, T.must(updated).free_trial_conversions
    end

    test "free trial cancellations includes cancellation during trial" do
      cancelled_subscription = create(:billing_subscription_item,
        :cancelled,
        subscribable: @paid_plan,
        free_trial_ends_on: yesterday + 1.week,
      )
      cancellation = create(:transaction,
        :mp_cancelled,
        user: cancelled_subscription.plan_subscription.user,
        old_subscribable: @paid_plan,
        old_subscribable_quantity: 1,
      )
      cancellation.update_column(:timestamp, yesterday_timestamp)

      insight = Marketplace::ListingInsight.new(listing: @listing, recorded_on: yesterday)
      insight.update_metrics!

      assert updated = Marketplace::ListingInsight.find_by(marketplace_listing_id: @listing.id, recorded_on: yesterday)
      assert_equal 1, T.must(updated).free_trial_cancellations
    end

    test "free trial cancellations includes manual downgrades to free plan during trial" do
      free_trial_subscription = create(:billing_subscription_item,
        :cancelled,
        subscribable: @paid_plan,
        free_trial_ends_on: yesterday + 1.week,
      )
      downgrade = create(:transaction,
        :mp_changed,
        user: free_trial_subscription.plan_subscription.user,
        old_subscribable: @paid_plan,
        old_subscribable_quantity: 1,
        current_subscribable: @free_plan,
        current_subscribable_quantity: 1,
      )
      downgrade.update_column(:timestamp, yesterday_timestamp)

      insight = Marketplace::ListingInsight.new(listing: @listing, recorded_on: yesterday)
      insight.update_metrics!

      assert updated = Marketplace::ListingInsight.find_by(marketplace_listing_id: @listing.id, recorded_on: yesterday)
      assert_equal 1, T.must(updated).free_trial_cancellations
    end

    test "updates for listings with no free trials or transactions" do
      plan = create(:marketplace_listing_plan, :verified_listing)
      listing = plan.listing

      insight = Marketplace::ListingInsight.new(listing: listing, recorded_on: yesterday)
      insight.update_metrics!

      refute_nil Marketplace::ListingInsight.find_by(marketplace_listing_id: listing.id, recorded_on: yesterday)
    end

    test "excludes transactions for listings that are not active/billable" do
      inactive_transaction = create(:transaction, :mp_purchased, current_subscribable: @paid_plan, active_listing: false)
      active_transaction = create(:transaction, :mp_purchased, current_subscribable: @paid_plan, active_listing: true)
      inactive_transaction.update_column(:timestamp, yesterday_timestamp)
      active_transaction.update_column(:timestamp, yesterday_timestamp)

      insight = Marketplace::ListingInsight.new(listing: @listing, recorded_on: yesterday)
      insight.update_metrics!(:transaction)

      assert recorded = Marketplace::ListingInsight.find_by(marketplace_listing_id: @listing.id, recorded_on: yesterday)
      assert_equal 1, T.must(recorded).new_purchases
    end

    test "excludes mrr_recurring transactions that have not yet succeeded" do
      line_items = []

      successful_transaction = create(:billing_transaction, transaction_type: "recurring-charge", last_status: :settled)
      line_items << create(:billing_transaction_line_item,
        billing_transaction: successful_transaction,
        subscribable: @paid_plan,
        quantity: 1,
        amount_in_cents: @paid_plan.monthly_price_in_cents,
      )

      unsuccessful_transaction = create(:billing_transaction, transaction_type: "recurring-charge", last_status: :authorizing)
      line_items << create(:billing_transaction_line_item,
        billing_transaction: unsuccessful_transaction,
        subscribable: @paid_plan,
        quantity: 1,
        amount_in_cents: @paid_plan.monthly_price_in_cents,
      )

      Billing::BillingTransaction::LineItem.where(id: line_items.map(&:id)).update_all(created_at: yesterday_timestamp)

      insight = Marketplace::ListingInsight.new(listing: @listing, recorded_on: yesterday)
      insight.update_metrics!(:transaction)

      assert recorded = Marketplace::ListingInsight.find_by(marketplace_listing_id: @listing.id, recorded_on: yesterday)
      assert_equal @paid_plan.monthly_price_in_cents, T.must(recorded).mrr_recurring
    end
  end

  context "updating installation insights" do
    test "records zeroes when no installs exist" do
      assert_nil Marketplace::ListingInsight.find_by(marketplace_listing_id: @listing.id, recorded_on: yesterday)

      insight = Marketplace::ListingInsight.new(listing: @listing, recorded_on: yesterday)
      insight.update_metrics!

      assert recorded = Marketplace::ListingInsight.find_by(marketplace_listing_id: @listing.id, recorded_on: yesterday)
      assert_equal 0, T.must(recorded).installs
    end

    test "creates a new record" do
      assert_nil Marketplace::ListingInsight.find_by(marketplace_listing_id: @listing.id, recorded_on: yesterday)

      auth = create(:oauth_authorization, application: @listing.listable)
      auth.update_column(:created_at, yesterday_timestamp)

      insight = Marketplace::ListingInsight.new(listing: @listing, recorded_on: yesterday)
      insight.update_metrics!

      assert recorded = Marketplace::ListingInsight.find_by(marketplace_listing_id: @listing.id, recorded_on: yesterday)
      assert_equal 1, T.must(recorded).installs
    end

    test "updates an existing record" do
      create(:marketplace_listing_insight, listing: @listing, recorded_on: yesterday)

      install = create(:oauth_authorization, application: @listing.listable)
      install.update_attribute(:created_at, yesterday_timestamp)

      refute_nil Marketplace::ListingInsight.find_by(marketplace_listing_id: @listing.id, recorded_on: yesterday)

      insight = Marketplace::ListingInsight.new(listing: @listing, recorded_on: yesterday)
      insight.update_metrics!

      assert recorded = Marketplace::ListingInsight.find_by(marketplace_listing_id: @listing.id, recorded_on: yesterday)
      assert_equal 1, T.must(recorded).installs
    end

    test "records installs for an integration" do
      integration_listing = create(:marketplace_listing, :integration)
      create(:marketplace_listing_plan, :free, listing: integration_listing)
      create(:marketplace_listing_plan, :free_trial, listing: integration_listing, has_free_trial: true)

      installation = make_integration_installation(integration: integration_listing.listable, target: create(:user))
      installation.update_attribute(:created_at, yesterday_timestamp)

      insight = Marketplace::ListingInsight.new(listing: integration_listing, recorded_on: yesterday)
      insight.update_metrics!

      assert recorded = Marketplace::ListingInsight.find_by(marketplace_listing_id: integration_listing.id, recorded_on: yesterday)
      assert_equal 1, T.must(recorded).installs
    end

    test "records installs for an OAuth application" do
      install = create(:oauth_authorization, application: @listing.listable)
      install.update_attribute(:created_at, yesterday_timestamp)

      insight = Marketplace::ListingInsight.new(listing: @listing, recorded_on: yesterday)
      insight.update_metrics!

      assert recorded = Marketplace::ListingInsight.find_by(marketplace_listing_id: @listing.id, recorded_on: yesterday)
      assert_equal 1, T.must(recorded).installs
    end

    test "can update only installation metrics" do
      transaction = create(:transaction, :mp_purchased, current_subscribable: @paid_plan)
      transaction.update_column(:timestamp, yesterday_timestamp)
      install = create(:oauth_authorization, application: @listing.listable)
      install.update_attribute(:created_at, yesterday_timestamp)

      insight = Marketplace::ListingInsight.new(listing: @listing, recorded_on: yesterday)
      insight.update_metrics!(:installation)

      assert recorded = Marketplace::ListingInsight.find_by(marketplace_listing_id: @listing.id, recorded_on: yesterday)
      recorded = T.must(recorded)
      assert_equal 0, recorded.new_purchases
      assert_equal 1, recorded.installs
      assert_equal 0, recorded.pageviews
    end
  end

  context "updating traffic insights" do
    test "creates a new record" do
      assert_nil Marketplace::ListingInsight.find_by(marketplace_listing_id: @listing.id, recorded_on: yesterday)
      insight = Marketplace::ListingInsight.new(listing: @listing, recorded_on: yesterday)

      # Presto will be queried 3 times, for pageviews/visitors, landing_uniques, checkout_uniques
      stubbed_presto_results = [[84, 42], [3], [9]].map { |rows| stub(run: [[], [rows]]) }
      GitHub.stubs(:presto).returns(*stubbed_presto_results)

      insight.update_metrics!

      assert recorded = Marketplace::ListingInsight.find_by(marketplace_listing_id: @listing.id, recorded_on: yesterday)
      recorded = T.must(recorded)
      assert_equal 84, recorded.pageviews
      assert_equal 42, recorded.visitors
      assert_equal 3, recorded.landing_uniques
      assert_equal 9, recorded.checkout_uniques
    end

    test "updates an existing record" do
      create(:marketplace_listing_insight, listing: @listing, recorded_on: yesterday)

      refute_nil Marketplace::ListingInsight.find_by(marketplace_listing_id: @listing.id, recorded_on: yesterday)

      insight = Marketplace::ListingInsight.new(listing: @listing, recorded_on: yesterday)

      # Presto will be queried 3 times, for pageviews/visitors, landing_uniques, checkout_uniques
      stubbed_presto_results = [[84, 42], [3], [9]].map { |rows| stub(run: [[], [rows]]) }
      GitHub.stubs(:presto).returns(*stubbed_presto_results)

      insight.update_metrics!

      assert recorded = Marketplace::ListingInsight.find_by(marketplace_listing_id: @listing.id, recorded_on: yesterday)
      recorded = T.must(recorded)
      assert_equal 84, recorded.pageviews
      assert_equal 42, recorded.visitors
      assert_equal 3, recorded.landing_uniques
      assert_equal 9, recorded.checkout_uniques
    end

    test "can update only traffic metrics" do
      transaction = create(:transaction, :mp_purchased, current_subscribable: @paid_plan)
      transaction.update_column(:timestamp, yesterday_timestamp)
      install = create(:oauth_authorization, application: @listing.listable)
      install.update_attribute(:created_at, yesterday_timestamp)

      insight = Marketplace::ListingInsight.new(listing: @listing, recorded_on: yesterday)

      # Presto will be queried 3 times, for pageviews/visitors, landing_uniques, checkout_uniques
      stubbed_presto_results = [[84, 42], [3], [9]].map { |rows| stub(run: [[], [rows]]) }
      GitHub.stubs(:presto).returns(*stubbed_presto_results)

      insight.update_metrics!(:traffic)

      assert recorded = Marketplace::ListingInsight.find_by(marketplace_listing_id: @listing.id, recorded_on: yesterday)
      recorded = T.must(recorded)
      assert_equal 0, recorded.new_purchases
      assert_equal 0, recorded.installs
      assert_equal 84, recorded.pageviews
      assert_equal 3, recorded.landing_uniques
      assert_equal 9, recorded.checkout_uniques
    end
  end

  def yesterday
    @yesterday ||= Date.yesterday
  end

  def yesterday_timestamp
    @yesterday_timestamp ||= yesterday.strftime("%Y-%m-%d 12:00:00")
  end
end
