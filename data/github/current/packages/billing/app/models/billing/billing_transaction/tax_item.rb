# typed: strict
# frozen_string_literal: true

module Billing
  class BillingTransaction::TaxItem < ApplicationRecord::Domain::Billing
    belongs_to :line_item,
      class_name: "Billing::BillingTransaction::LineItem",
      foreign_key: :billing_transaction_line_item_id,
      inverse_of: :tax_items
  end
end
