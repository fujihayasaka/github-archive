# typed: true
# frozen_string_literal: true

class BillingChargeJob < ApplicationJob
  queue_as :billing

  discard_on ActiveRecord::RecordNotFound

  def perform(user_or_business)
    GitHub.logger.info(
      "code.namespace" => self.class.name,
      "code.function" => "perform",
      "gh.billing.billable_entity.id" => user_or_business.id,
      "gh.billing.billable_entity.type" => user_or_business.class.name,
    )

    with_write { user_or_business.recurring_charge }
  end
end
