# typed: true
# frozen_string_literal: true

require "test_helper"

class MarketplaceListingTransactionsReportTest < GitHub::TestCase
  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @listing = create(:marketplace_listing, :with_paid_plan)
    @listing2 = create(:marketplace_listing, :with_paid_plan)
    @report = Marketplace::ListingTransactionsReport.new \
      listing_id:   @listing.id,
      listing_slug: @listing.slug

    @headers = %w[
      date
      app_name
      user_login
      user_id
      user_type
      country
      amount_in_cents
      renewal_frequency
      marketplace_listing_plan_id
      region
      postal_code
    ]
  end

  setup do
    column_stubs = @headers.map { |header_name| stub(name: header_name) }
    row_stubs = []

    GitHub
      .stubs(:presto)
      .returns(stub(run: [column_stubs, row_stubs]))
  end

  context "#filename" do
    test "generates a filename" do
      Timecop.freeze(Date.today) do
        report = Marketplace::ListingTransactionsReport.new \
          listing_id:   @listing.id,
          listing_slug: @listing.slug
        name = "#{@listing.slug}-transactions-#{Date.today.strftime "%Y-%m"}.csv"
        assert_equal name, report.filename
      end
    end
  end

  context "#period" do
    test "accepts a valid period" do
      report_with_valid_period = Marketplace::ListingTransactionsReport.new \
        listing_id:   @listing.id,
        listing_slug: @listing_slug,
        period:       "day"

      assert_equal :day, report_with_valid_period.period
    end

    test "uses default period when no period is given" do
      report_with_no_period = Marketplace::ListingTransactionsReport.new \
        listing_id:   @listing.id,
        listing_slug: @listing_slug

      assert_equal :week, report_with_no_period.period
    end

    test "uses default period when an invalid period is given" do
      report_with_invalid_period = Marketplace::ListingTransactionsReport.new \
        listing_id:   @listing.id,
        listing_slug: @listing_slug,
        period:       "invalid"

      assert_equal :week, report_with_invalid_period.period
    end
  end

  context "#period_title" do
    test "returns correct title when a valid period is given" do
      report_with_valid_period = Marketplace::ListingTransactionsReport.new \
        listing_id:   @listing.id,
        listing_slug: @listing_slug,
        period:       "day"

      assert_equal "Past Day", report_with_valid_period.period_title
    end

    test "uses default period title when no period is given" do
      report_with_no_period = Marketplace::ListingTransactionsReport.new \
        listing_id:   @listing.id,
        listing_slug: @listing_slug

      assert_equal "Past Week", report_with_no_period.period_title
    end

    test "uses default period title when an invalid period is given" do
      report_with_invalid_period = Marketplace::ListingTransactionsReport.new \
        listing_id:   @listing.id,
        listing_slug: @listing_slug,
        period:       "invalid"

      assert_equal "Past Week", report_with_invalid_period.period_title
    end
  end

  context "#as_csv", skip_enterprise: true do
    test "returns a string-rendered csv" do
      GitHub.flipper[:new_listing_transactions_query].disable
      assert_match @headers.join(","), @report.as_csv.split("\n").first
    end

    test "fills in user information if transaction linked to enterprise user" do
      GitHub.flipper[:new_listing_transactions_query].enable
      business = create(:business)
      transaction = create(:billing_transaction, :business_owned, customer: business.customer)
      line_item = create(:billing_transaction_line_item,
        :marketplace_listing,
        billing_transaction: transaction
      )

      report = Marketplace::ListingTransactionsReport.new \
        listing_id:  line_item.subscribable.listing.id,
        listing_slug: line_item.subscribable.listing.slug,
        period: "alltime",
        plan_type: "All plans"

      csv = report.as_csv
      assert csv
      csv_items = CSV.parse(csv)
      item = csv_items[1]

      assert item
      assert_equal transaction.created_at.strftime("%Y-%m-%d"), T.must(item)[0]
      assert_equal line_item.subscribable.listing.name, T.must(item)[1]
      assert_equal business.customer.name, T.must(item)[2]
      assert_equal business.customer.id.to_s, T.must(item)[3]
      assert_equal "Enterprise", T.must(item)[4]
      assert_nil T.must(item)[5]
      assert_equal line_item.amount_in_cents.to_s, T.must(item)[6]
      assert_equal transaction.renewal_frequency, T.must(item)[7]
      assert_equal line_item.subscribable.id.to_s, T.must(item)[8]
    end
  end

  context "#as_blob" do
    test "returns a list of transactions with headers" do
      GitHub.flipper[:new_listing_transactions_query].disable
      assert_equal [@headers], @report.as_blob
    end
  end

  context "#empty?" do
    test "returns true if the report only has headers" do
      assert @report.empty?
    end
  end

  context "#column_names" do
    test "returns the column names" do
      assert_equal %w(date app_name user_login user_id user_type country amount_in_cents renewal_frequency marketplace_listing_plan_id region postal_code), @report.column_names
    end
  end

  context "fetch transactions", skip_enterprise: true do
    test "returns the right transactions when the ff is enabled" do
      Timecop.freeze do
        GitHub.flipper[:advanced_transaction_filtering].enable
        GitHub.flipper[:new_listing_transactions_query].enable
        plan = @listing.listing_plans.first
        create_list(:billing_transaction_line_item,
          2,
          :marketplace_listing,
          subscribable: plan,
          created_at: 1.day.ago
        )
        create_list(:billing_transaction_line_item,
          2,
          :marketplace_listing,
          subscribable: plan,
          created_at: 1.week.ago
        )
        report = Marketplace::ListingTransactionsReport.new \
                  listing_id:   @listing.id,
                  listing_slug: @listing.slug,
                  period:       "alltime",
                  plan_type: "All plans"

        assert_equal 4, report.send(:fetch_transactions).size
      end
    end

    test "returns the right transactions when the ff is enabled and period is not all time" do
      Timecop.freeze do
        GitHub.flipper[:new_listing_transactions_query].enable
        plan = @listing.listing_plans.first
        included_line_items = create_list(:billing_transaction_line_item,
          2,
          :marketplace_listing,
          subscribable: plan,
          created_at: 1.day.ago
        )
        not_included_line_items = create_list(:billing_transaction_line_item,
          2,
          :marketplace_listing,
          subscribable: plan,
          created_at: 1.week.ago
        )
        report = Marketplace::ListingTransactionsReport.new \
                  listing_id:   @listing.id,
                  listing_slug: @listing.slug,
                  period:       "day",
                  plan_type: "All plans"

        transactions = report.send(:fetch_transactions)
        assert_equal 2, transactions.size
        assert_equal included_line_items.pluck(:created_at), transactions.pluck(:created_at)
        refute_equal not_included_line_items.pluck(:created_at), transactions.pluck(:created_at)
      end
    end

    test "returns transactions for a specific listing_plan" do
      GitHub.flipper[:new_listing_transactions_query].enable
      GitHub.flipper[:advanced_transaction_filtering].enable

      selected_plan = @listing.listing_plans.first
      non_selected_plan = @listing2.listing_plans.last

      listing_plan_line_items = create_list(:billing_transaction_line_item,
        1,
        :marketplace_listing,
        subscribable: selected_plan,
        created_at: 1.day.ago
      )

      non_listing_plan_line_items = create_list(:billing_transaction_line_item,
        2,
        :marketplace_listing,
        subscribable: non_selected_plan,
        created_at: 1.day.ago
      )

      report = Marketplace::ListingTransactionsReport.new \
      listing_id:   @listing.id,
      listing_slug: @listing.slug,
      period:       "alltime",
      plan_type:    selected_plan.id.to_s

      transactions = report.send(:fetch_transactions)
      assert_equal 1, transactions.size
      assert_equal selected_plan.id, transactions.first.subscribable_id
    end

    test "limits the number of transactions returned" do
      Marketplace::ListingTransactionsReport.stub_const(:MAX_TRANSACTIONS_SIZE, 1) do
        GitHub.flipper[:new_listing_transactions_query].enable
        plan = @listing.listing_plans.first
        create_list(:billing_transaction_line_item,
          2,
          :marketplace_listing,
          subscribable: plan,
        )

        report = Marketplace::ListingTransactionsReport.new \
                  listing_id:   @listing.id,
                  listing_slug: @listing.slug,
                  period:       "alltime",
                  plan_type:    "All plans"

        assert_equal 1, report.send(:fetch_transactions).size
      end
    end

    test "does limits the number of transactions returned if truncate is false" do
      Marketplace::ListingTransactionsReport.stub_const(:MAX_TRANSACTIONS_SIZE, 1) do
        GitHub.flipper[:new_listing_transactions_query].enable
        plan = @listing.listing_plans.first
        create_list(:billing_transaction_line_item,
          2,
          :marketplace_listing,
          subscribable: plan,
        )

        report = Marketplace::ListingTransactionsReport.new \
                  listing_id:   @listing.id,
                  listing_slug: @listing.slug,
                  period:       "alltime",
                  plan_type:    "All plans"

        assert_equal 2, report.truncate(false).send(:fetch_transactions).size
      end
    end
  end
end
