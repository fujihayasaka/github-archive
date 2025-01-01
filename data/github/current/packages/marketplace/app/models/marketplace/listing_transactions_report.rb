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
    if GitHub.flipper[:new_listing_transactions_query].enabled?(@current_user)
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
    else
      CSV.generate do |csv|
        csv << data.first.map(&:name) # use the column names as headers
        data.second.each { |transaction| csv << transaction }
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
    if GitHub.flipper[:new_listing_transactions_query].enabled?(@current_user)
      query
    else
      GitHub.presto.run(query)
    end
  end

  def fetch_customers(transactions)
    ids = transactions.map { |t| t.attributes["customer_id"] }.uniq.compact
    Customer.where(id: ids).pluck(:id, :name)
  end

  def query
    if GitHub.flipper[:advanced_transaction_filtering].enabled?(@current_user)
      if @plan_type.nil? || @plan_type == "All plans"
        plan_ids = Marketplace::ListingPlan.where(listing_id: @listing_id).pluck(:id)
      else
        plan_ids = [@plan_type.to_i]
      end
    else
      plan_ids = Marketplace::ListingPlan.where(listing_id: @listing_id).pluck(:id)
    end

    if GitHub.flipper[:new_listing_transactions_query].enabled?(@current_user)
      max = @truncate ? MAX_TRANSACTIONS_SIZE : nil
      plan_ids = Marketplace::ListingPlan.where(listing_id: @listing_id).pluck(:id)
      sort = @sort_type == "latest" || @sort_type.nil? ? "DESC" : "ASC"
      query = if period != :alltime
        Billing::BillingTransaction::LineItem.marketplace
          .joins(:billing_transaction)
          .select(SELECT_FIELDS)
          .where(
            billing_transactions: {
              last_status: Billing::BillingTransactionStatuses::SUCCESS[:settled]
            },
            billing_transaction_line_items: {
              subscribable_id: plan_ids,
              created_at: (latest_available_date - PERIOD_OFFSET_MAPPING[@period])...
            }
          )
          .limit(max)
          .order("billing_transaction_line_items.created_at #{sort}")
      else
        Billing::BillingTransaction::LineItem.marketplace
          .joins(:billing_transaction)
          .select(SELECT_FIELDS)
          .where(
            billing_transactions: {
              last_status: Billing::BillingTransactionStatuses::SUCCESS[:settled]
            },
            billing_transaction_line_items: {
              subscribable_id: plan_ids
            }
          )
          .limit(max)
          .order("billing_transaction_line_items.created_at #{sort}")
      end
      query = query.where("billing_transactions.user_login LIKE ?", "%#{@user_name}%") unless @user_name == ""
      query
    else
      %Q(
        SELECT
          DATE(created_at) AS date,
          app_name,
          user_login,
          user_id,
          user_type,
          country,
          amount_in_cents,
          renewal_frequency,
          subscribable_id as marketplace_listing_plan_id,
          region,
          postal_code
        FROM
          hive.service_strategic_finance.marketplace_billing_transactions
        WHERE
          marketplace_listing_id = #{@listing_id}
          #{query_period_filter}
        ORDER BY
          date DESC
        #{query_limit}
      )
    end
  end

  def count_total_transactions
    if GitHub.flipper[:new_listing_transactions_query].enabled?(@current_user)
      count_query
    else
      _, rows = GitHub.presto.run(count_query)
      # grab the first row then the first column, which should be the count
      rows.first&.first&.to_i || 0
    end
  end

  def count_query
    if GitHub.flipper[:new_listing_transactions_query].enabled?(@current_user)
      if @plan_type.nil? || @plan_type == "All plans"
        plan_ids = Marketplace::ListingPlan.where(listing_id: @listing_id).pluck(:id)
      else
        plan_ids = [@plan_type.to_i]
      end
      query = Billing::BillingTransaction::LineItem.successful.where(listing_id: @listing_id, subscribable_id: plan_ids, listing_type: "Marketplace::Listing").count
    else
      %Q(
        SELECT
          COUNT(*)
        FROM
          hive.service_strategic_finance.marketplace_billing_transactions
        WHERE
          marketplace_listing_id = #{@listing_id}
          #{query_period_filter}
      )
    end
  end

  def query_period_filter
    return if @period == :alltime

    offset = PERIOD_OFFSET_MAPPING[@period]
    start_date = query_date_format(latest_available_date - offset)
    end_date = query_date_format(latest_available_date)

    "AND created_at BETWEEN date '#{start_date}' AND date '#{end_date}'"
  end

  def query_date_format(date)
    date.strftime("%Y-%m-%d")
  end

  def latest_available_date
    Date.current - 2.days
  end

  def query_limit
    return unless @truncate
    "LIMIT #{MAX_TRANSACTIONS_SIZE}"
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
