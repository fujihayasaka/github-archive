# typed: strict
# frozen_string_literal: true

module Billing::MultiUserBudgetCheck
  COPILOT_PRICING_TARGET_IDS = T.let(%w[copilot_premium_request premium_requests].freeze, T::Array[String])

  # Checks whether the given org or business already has a Copilot multi-user
  # budget for any known pricing target ID. The per-customer result is cached via
  # Billing::Cache::CopilotMultiUserBudgetClient to avoid billing-platform API
  # round-trips on every page render: confirmed results are cached for the full
  # TTL, and undetermined results (a request failed) for the shorter error TTL so
  # an outage stays cheap without pinning a wrong answer for an hour.
  sig { params(entity: ::Billing::Types::OrgOrBusiness).returns(T::Boolean) }
  def self.has_copilot_multi_user_budget?(entity)
    customer_id = entity.customer&.id.to_s
    return false if customer_id.blank?

    state = Billing::Cache::CopilotMultiUserBudgetClient.new(customer_id).fetch do
      case fetch_copilot_multi_user_budget(entity, customer_id)
      when true
        Billing::Cache::CopilotMultiUserBudgetClient::HAS_BUDGET
      when false
        Billing::Cache::CopilotMultiUserBudgetClient::NO_BUDGET
      else
        # Undetermined: at least one billing-platform request failed. The client
        # caches this briefly so repeated renders during an outage stay cheap but
        # re-check soon in case the entity has a budget.
        Billing::Cache::CopilotMultiUserBudgetClient::UNDETERMINED
      end
    end

    state == Billing::Cache::CopilotMultiUserBudgetClient::HAS_BUDGET
  rescue => e
    Failbot.report(e)
    false
  end

  # Returns true if a budget exists, false if every pricing target was checked
  # successfully and none had a budget, or nil if no budget was found but at
  # least one billing-platform request failed (an undetermined result the caller
  # maps to UNDETERMINED and caches only briefly).
  sig { params(entity: ::Billing::Types::OrgOrBusiness, customer_id: String).returns(T.nilable(T::Boolean)) }
  def self.fetch_copilot_multi_user_budget(entity, customer_id)
    client = Billing::Platform::Api::Client.new(timeout: 2)
    encountered_error = T.let(false, T::Boolean)

    COPILOT_PRICING_TARGET_IDS.each do |target_id|
      response = client.get_all_budgets(
        customer_id: customer_id,
        scope: "multi_user_customer",
        budget_target: target_id,
        page_size: 1,
        use_remote_cache: true,
        feature_flag_target: entity,
        include_total_count: false
      )

      if response.is_a?(Billing::Platform::Api::Error)
        encountered_error = true
        next
      end

      return true if response[:budgets].present?
    end

    encountered_error ? nil : false
  end
  private_class_method :fetch_copilot_multi_user_budget
end
