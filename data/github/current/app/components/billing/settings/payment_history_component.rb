# typed: true
# frozen_string_literal: true

class Billing::Settings::PaymentHistoryComponent < ApplicationComponent
  attr_reader :payment_records, :has_payment_method

  def initialize(payment_records:, has_payment_method:)
    @payment_records = payment_records
    @has_payment_method = has_payment_method
  end

  private

  def render?
    @has_payment_method && @payment_records.present?
  end

  def record_tooltip(record)
    # add additional context for refunds
    return record.status.capitalize + " for #{record.sale.short_transaction_id}" if record.sale.present?
    # default tooltip content to the status of the transaction
    record.status.capitalize
  end
end
