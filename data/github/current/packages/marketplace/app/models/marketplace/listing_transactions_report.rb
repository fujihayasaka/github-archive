# typed: true
# frozen_string_literal: true

class Marketplace::ListingTransactionsReport
  DEFAULT_PERIOD = :week
  DEFAULT_PLAN = :all
  DEFAULT_PLAN_TITLE = "All Plans"
  VALID_PERIODS = %i(day week month alltime)
  PERIOD_OFFSET_MAPPING = { day: 0, week: 6, month: 29 }
  MAX_TRANSACTIONS_SIZE = 100
  DEFAULT_PERIOD_TITLE = "Past Week"
  VALID_PERIOD_TITLES = {
    day:     "Past Day",
    week:    "Past Week",
    month:   "Past Month",
    alltime: "All-time",
  }
  SELECT_FIELDS = [
    "billing_transaction_line_items.created_at",
    "billing_transactions.customer_id",
    "billing_transactions.user_login",
    "billing_transactions.user_id",
    "billing_transactions.user_type",
    "billing_transactions.country",
    "billing_transaction_line_items.amount_in_cents",
    "billing_transactions.renewal_frequency",
    "billing_transaction_line_items.subscribable_id",
    "billing_transactions.region",
    "billing_transactions.postal_code",
  ]

  attr_reader :filename, :period, :period_title, :plan_type

  def initialize(listing_id:, listing_slug:, plan_type: DEFAULT_PLAN_TITLE, sort_type: nil, period: DEFAULT_PERIOD, user: nil, user_name: "")
    @listing_id = listing_id
    @listing_slug = listing_slug
    @listing_name = Marketplace::Listing.find(@listing_id).name
    @filename = generate_filename(@listing_slug)
    @period = validate_period(period.to_s)
    @period_title = validate_period_title(@period)
    @transactions_count = count_total_transactions
    @truncate = true
    @current_user = user
    @sort_type = sort_type
    @plan_type = plan_type
    @user_name = user_name
  end

  def as_csv
    data = fetch_transactions
    customers = fetch_customers(data)
    CSV.generate do |csv|
      csv << column_names
      # changing the date format since active record returns DateTime objects
      # Adding listing name as the second value in the row since we cannot join listing table with line item table
      data.each do |transaction|
        row = transaction.attributes.except("customer_id", "billing_transaction_id").values
        customer_id = transaction.attributes["customer_id"]
        row[0] = row[0].strftime("%Y-%m-%d")
        row.insert(1, @listing_name)

        # need to manually update renewal frequency since it is stored as an integer
        row[7] = row[7] == 0 ? "monthly" : "yearly"

        # Enterprise customer logins are not saved in transaction data
        unless transaction.attributes["user_id"].present?
          customer = customers.find { |c| c[0] == customer_id }
          if customer
            row[2] = customer[1]
            row[3] = customer[0]
            row[4] = "Enterprise"
          end
        end
        csv << row
      end
    end
  end

  def any_plan_type?(plan_type)
    plan_type == "Any plan"
  end

  def column_names
    %w(date app_name user_login user_id user_type country amount_in_cents renewal_frequency marketplace_listing_plan_id region postal_code)
  end

  def as_blob
    CSV.parse(as_csv)
  end

  def truncate(val = true)
    @truncate = val
    self
  end

  def empty?
    @transactions_count.zero?
  end

  def too_large?
    @transactions_count > MAX_TRANSACTIONS_SIZE
  end

  def valid_periods
    VALID_PERIOD_TITLES
  end

  private

  def fetch_transactions
    # GitHub.presto.run returns a [columns, rows] pair
    query
  end

  def fetch_customers(transactions)
    ids = transactions.map { |t| t.attributes["customer_id"] }.uniq.compact
    Customer.where(id: ids).pluck(:id, :name)
  end

  def query
    if FeatureFlag.vexi.enabled?(:advanced_transaction_filtering, @current_user, default: false)
      if @plan_type.nil? || @plan_type == "All plans"
        plan_ids = Marketplace::ListingPlan.where(listing_id: @listing_id).pluck(:id)
      else
        plan_ids = [@plan_type.to_i]
      end
    else
      plan_ids = Marketplace::ListingPlan.where(listing_id: @listing_id).pluck(:id)
    end

    max = @truncate ? MAX_TRANSACTIONS_SIZE : nil
    plan_ids = Marketplace::ListingPlan.where(listing_id: @listing_id).pluck(:id)
    sort = @sort_type == "latest" || @sort_type.nil? ? "DESC" : "ASC"
    query = if period != :alltime
      Billing::BillingTransaction::LineItem.marketplace
        .joins(:billing_transaction)
        .select(SELECT_FIELDS)
        .where(
          billing_transaction_line_items: {
            subscribable_id: plan_ids,
            created_at: (latest_available_date - PERIOD_OFFSET_MAPPING[@period])...
          },
          billing_transactions: {
            last_status: Billing::BillingTransactionStatuses::SUCCESS[:settled]
          }
        )
        .limit(max)
        .order("billing_transaction_line_items.created_at #{sort}")
    else
      Billing::BillingTransaction::LineItem.marketplace
        .joins(:billing_transaction)
        .select(SELECT_FIELDS)
        .where(
          billing_transaction_line_items: {
            subscribable_id: plan_ids
          },
          billing_transactions: {
            last_status: Billing::BillingTransactionStatuses::SUCCESS[:settled]
          }
        )
        .limit(max)
        .order("billing_transaction_line_items.created_at #{sort}")
    end
    query = query.where("billing_transactions.user_login LIKE ?", "%#{@user_name}%") unless @user_name == ""
    query
  end

  def count_total_transactions
    count_query
  end

  def count_query
    if @plan_type.nil? || @plan_type == "All plans"
      plan_ids = Marketplace::ListingPlan.where(listing_id: @listing_id).pluck(:id)
    else
      plan_ids = [@plan_type.to_i]
    end

    number_of_batches = 10
    total_line_items_count = 0

    (0...number_of_batches).each do |i|
      partial_line_items_count = Billing::BillingTransaction::LineItem.where(
        listing_id: @listing_id,
        subscribable_id: plan_ids,
        listing_type: "Marketplace::Listing"
      )
      .where("billing_transaction_id % ? = ?", number_of_batches, i).successful.count
      total_line_items_count += partial_line_items_count
    end

    total_line_items_count
  end

  def latest_available_date
    Date.current - 2.days
  end

  def validate_period(raw_period)
    VALID_PERIODS.find { |period| period.to_s == raw_period } || DEFAULT_PERIOD
  end

  def validate_period_title(raw_period)
    VALID_PERIOD_TITLES.fetch(raw_period, DEFAULT_PERIOD_TITLE)
  end

  def generate_filename(slug)
    "#{slug}-transactions-#{Date.today.strftime "%Y-%m"}.csv"
  end
end
