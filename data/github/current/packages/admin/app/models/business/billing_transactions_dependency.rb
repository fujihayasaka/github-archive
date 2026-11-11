# typed: true
# frozen_string_literal: true

require "github/billing"

module Business::BillingTransactionsDependency
  extend ActiveSupport::Concern
  extend T::Helpers
  requires_ancestor { Business }

  included do
    T.bind(self, T.class_of(Business))
    has_many :billing_transactions, through: :customer, class_name: "Billing::BillingTransaction"
    has_many :billing_transactions_sales, -> { T.bind(self, T.untyped); sales }, through: :customer, source: :business, class_name: "Billing::BillingTransaction"
    has_many :line_items, through: :billing_transactions, class_name: "Billing::BillingTransaction::LineItem"
  end
end
