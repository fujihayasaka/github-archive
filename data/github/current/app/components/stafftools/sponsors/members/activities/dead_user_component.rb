# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::Members::Activities::DeadUserComponent < ApplicationComponent

  def initialize(activity:)
    @activity = activity
  end

  private

  def render?
    @activity.present?
  end

  def title
    "#{dead_user.login} (deleted)"
  end

  memoize def dead_user
    most_recent_billing_transaction&.dead_user
  end

  memoize def most_recent_billing_transaction
    Billing::BillingTransaction.for_user(@activity.sponsor_id).last
  end
end
