# typed: strict
# frozen_string_literal: true

module Copilot
  class OverageBudgetDialogComponent < ApplicationComponent
    sig { returns(T.nilable(String)) }
    attr_reader :budget_uuid

    sig { returns(Integer) }
    attr_reader :budget_amount

    sig { returns(String) }
    attr_reader :budgets_url

    sig { returns(String) }
    attr_reader :customer_id

    sig { returns(String) }
    attr_reader :pricing_target_id

    sig do
      params(
        budget_uuid: T.nilable(String),
        budget_amount: Integer,
        budgets_url: String,
        customer_id: String,
        pricing_target_id: String,
      ).void
    end
    def initialize(budget_uuid:, budget_amount:, budgets_url:, customer_id:, pricing_target_id:)
      @budget_uuid = budget_uuid
      @budget_amount = budget_amount
      @budgets_url = budgets_url
      @customer_id = customer_id
      @pricing_target_id = pricing_target_id
    end
  end
end
