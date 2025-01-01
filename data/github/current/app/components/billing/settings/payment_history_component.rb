# typed: strict
# frozen_string_literal: true

class Billing::Settings::PaymentHistoryComponent < ApplicationComponent
  sig { returns(T::Array[Billing::Settings::PaymentHistory::PaymentRecord]) }
  attr_reader :payment_records

  sig { returns(Billing::Types::Account) }
  attr_reader :target


  sig { params(payment_records: T::Array[Billing::Settings::PaymentHistory::PaymentRecord], target: Billing::Types::Account).void }
  def initialize(payment_records:, target:)
    @payment_records = payment_records
    @target = target
  end

  sig { returns(T::Boolean) }
  def has_payment_method?
    !!@target.payment_method
  end

  sig { returns(T::Boolean) }
  def can_download_invoice?
    @target.feature_enabled?(:billing_self_serve_invoice_download)
  end

  sig { params(transaction_id: Integer).returns(String) }
  def download_invoice_path(transaction_id:)
    if target.business?
      self_serve_business_billing_download_invoices_path(target, transaction_id:)
    elsif target.organization?
      org_billing_download_invoices_path(target, transaction_id:)
    else
      user_billing_download_invoices_path(target, transaction_id:)
    end
  end

  private

  sig { returns(T::Boolean) }
  def render?
    has_payment_method? && @payment_records.present?
  end

  sig { params(record: Billing::Settings::PaymentHistory::PaymentRecord).returns(String) }
  def record_tooltip(record)
    # add additional context for refunds
    return record.status.capitalize + " for #{record.sale.short_transaction_id}" if record.sale.present?
    # default tooltip content to the status of the transaction
    record.status.capitalize
  end
end
