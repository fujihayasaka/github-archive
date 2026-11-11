# typed: strict
# frozen_string_literal: true

module Billing::MultiUserBudgetCheck
  extend T::Helpers

  requires_ancestor { ApplicationController }

  sig { params(entity: ::Billing::Types::Account).returns(T::Boolean) }
  def has_multi_user_customer_budget?(entity)
    return false unless entity.feature_flag_enabled?(:billing_user_level_budgets_manage, default: false)

    customer_id = entity.customer&.id.to_s
    return false if customer_id.blank?

    client = Billing::Platform::Api::Client.new
    response = client.get_all_budgets(
      customer_id: customer_id,
      scope: "multi_user_customer",
      page_size: 1,
      use_remote_cache: true,
      feature_flag_target: entity
    )
    return false if response.is_a?(Billing::Platform::Api::Error)

    budgets = response[:budgets]
    budgets.present? && budgets.any?
  rescue => e # rubocop:todo Lint/RescueException
    Failbot.report(e)
    false
  end
end
