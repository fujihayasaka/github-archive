# typed: true
# frozen_string_literal: true

module Sponsors
  class InvoicedCustomerMetadata
    # line_items - Array of Billing::BillingTransaction::LineItems
    def initialize(line_items:)
      @line_items = line_items
    end

    # These consts are configuration options that help the @insights/column-chart library interpret our data
    MONTHNAMES = Date::ABBR_MONTHNAMES.freeze
    ONE_TIME_SERIES_NAME = "one-time"
    RECURRING_SERIES_NAME = "recurring"
    MONTH_COLUMN_NAME = "month"
    SPONSORSHIP_AMOUNT_COLUMN_NAME = "sponsorship_amount"
    SPONSORSHIP_TYPE_COLUMN_NAME = "sponsorship_type"
    VARCHAR_DATATYPE = "nvarchar"
    INT_DATATYPE = "int"

    # Public: Aggregate data about amount spent in each month
    #
    # month     - String
    # recurring - Integer: total dollars spent on recurring payments in a given month
    # one_time  - Integer: total dollars spent on one-time payments in a given month
    # total     - Integer: total dollars spent on all payments in a given month
    #
    # Returns an Array of hashes
    def aggregate_monthly_payments_in_dollars
      (1..12).map do |month|
        {
          month: MONTHNAMES[month],
          recurring: recurring_spend_per_month(month),
          one_time: one_time_spend_per_month(month),
          total: total_spend_per_month(month)
        }
      end
    end

    # Public: All of the monthly payments for the customer
    #
    # Returns and Array of Arrays, each containing:
    #   Month name    - The name of the month that the Billing::BillingTransaction::LineItem was created
    #   Dollar amount - monthly_price_in_cents of the Billing::BillingTransaction::LineItem, in dollars
    #   Tier type     - the String "recurring", if the tier is recurring, else the string "one-time"
    #
    #   Ex: ["Jan", 100, "recurring"]
    def monthly_payments_in_dollars
      aggregate_monthly_payments_in_dollars
        .flat_map { |payment| format_series_data(payment) }
    end

    # Public: The total amount spent during the given year
    #
    # Returns an Integer
    def aggregate_yearly_payments_in_dollars
      aggregate_monthly_payments_in_dollars.sum { |payment| payment[:total] }
    end

    # Public: The type annotations of the series data that will be returned
    #
    # Month name         - String
    # Sponsorship Amount - Integer
    # Sponsorship Type   - "one_time" | "recurring"
    #
    # Returns an Array of hashes
    #
    def column_types
      [month_column, sponsorship_amount_column, sponsorship_type_column]
    end

    private

    # Private: Type annotation for the monthly series data
    #
    # Returns hash of column name and datatype
    def month_column
      { name: MONTH_COLUMN_NAME, dataType: VARCHAR_DATATYPE }
    end

    # Private: Type annotation for the monthly series data
    #
    # Returns hash of column name and datatype
    def sponsorship_amount_column
      { name: SPONSORSHIP_AMOUNT_COLUMN_NAME, dataType: INT_DATATYPE }
    end

    # Private: Type annotation for the monthly series data
    #
    # Returns hash of column name and datatype
    def sponsorship_type_column
      { name: SPONSORSHIP_TYPE_COLUMN_NAME, dataType: VARCHAR_DATATYPE }
    end

    # Private: How much money was spent on recurring sponsorships in a given
    # month
    #
    # Returns Integer
    def recurring_spend_per_month(month)
      price_in_cents = recurring_items_for_month(month).sum(&:amount_in_cents)
      Billing::Money.new(price_in_cents).dollars.round
    end

    # Private: How much money was spent on one-time sponsorships in a given
    # month
    #
    # Returns Integer
    def one_time_spend_per_month(month)
      price_in_cents = one_time_items_for_month(month).sum(&:amount_in_cents)
      Billing::Money.new(price_in_cents).dollars.round
    end

    # Private: How much money was spent on all sponsorships in a given month
    #
    # Returns Integer
    def total_spend_per_month(month)
      price_in_cents = items_for_month(month).sum(&:amount_in_cents)
      Billing::Money.new(price_in_cents).dollars.round
    end

    # Private: Series data for transactions by both
    #
    # Ex: ["January", 100, "recurring"]
    #
    # Returns an Array of Tuples
    def format_series_data(payment_info)
      [
        [payment_info[:month], payment_info[:recurring], RECURRING_SERIES_NAME],
        [payment_info[:month], payment_info[:one_time], ONE_TIME_SERIES_NAME]
      ]
    end

    # Private: All line items that were created in a given month
    #
    # Returns an Array of Billing::BillingTransaction::LineItems
    def items_for_month(month)
      @line_items.filter { |i| i.created_at.month == month }
    end

    # Private: All line items that were created for recurring payments in a given month
    #
    # Returns an Array of Billing::BillingTransaction::LineItems
    def recurring_items_for_month(month)
      recurring_line_items.filter { |i| i.created_at.month == month }
    end

    # Private: All line items that were created for one-time payments in a given month
    #
    # Returns an Array of Billing::BillingTransaction::LineItems
    def one_time_items_for_month(month)
      one_time_line_items.filter { |i| i.created_at.month == month }
    end

    # Private: Convert cents into dollars
    #
    # Returns Integer
    def dollar_amount_for(cents)
      Billing::Money.new(cents).dollars.round
    end

    # Private: The line items associated to a one-time sponsors tier
    def one_time_line_items
      @one_time_line_items ||= @line_items.filter(&:one_time?)
    end

    # Private: The line items associated to a recurring sponsors tier
    def recurring_line_items
      @recurring_line_items ||= @line_items.filter(&:recurring?)
    end
  end
end
