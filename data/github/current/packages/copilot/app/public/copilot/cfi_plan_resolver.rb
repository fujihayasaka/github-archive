# typed: strict
# frozen_string_literal: true

module Copilot
  module CfiPlanResolver
    PRODUCT_KEY_TO_COPILOT_PLAN = T.let({
      Copilot::INDIVIDUAL_PRO_PRODUCT_KEY => BillingPlatform::Base::CopilotPlan::INDIVIDUAL,
      Copilot::INDIVIDUAL_PRO_PLUS_PRODUCT_KEY => BillingPlatform::Base::CopilotPlan::INDIVIDUAL_PRO_PLUS,
      Copilot::INDIVIDUAL_MAX_PRODUCT_KEY => BillingPlatform::Base::CopilotPlan::INDIVIDUAL_MAX,
      Copilot::EDU_PRODUCT_KEY => BillingPlatform::Base::CopilotPlan::INDIVIDUAL_EDU,
    }.freeze, T::Hash[String, Integer])

    sig { params(copilot_user: Copilot::User).returns(T.nilable(Integer)) }
    def self.resolve(copilot_user)
      product_key = copilot_user.copilot_active_subscription_item&.product_identifier&.product_key
      return nil unless product_key

      PRODUCT_KEY_TO_COPILOT_PLAN[product_key]
    end
  end
end
