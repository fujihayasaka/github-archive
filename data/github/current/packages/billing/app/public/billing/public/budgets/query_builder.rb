# typed: strict
# frozen_string_literal: true

module Billing::Public::Budgets::QueryBuilder
  extend T::Sig

  sig { params(business: Business, customer_id: T.nilable(String)).returns(T::Hash[Symbol, T.untyped]) }
  def self.index(business, customer_id: business.customer_id.to_s)
    budget_filters = {
      customer_id: customer_id,
    }

    budget_filters
  end
end
