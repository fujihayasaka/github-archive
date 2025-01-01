# typed: strict
# frozen_string_literal: true

class Billing::SalesServeSubscriptionChangeRequestItem < ApplicationRecord::Domain::Billing
  belongs_to :change_request, class_name: "Billing::SalesServeSubscriptionChangeRequest", inverse_of: :items, required: true

  validates_presence_of :status, :product_rate_plan_charge_id, :change_type, :start_date, :end_date

  enum :status, { unknown: 0, pending: 1, error: 2, complete: 3 }, prefix: true
  enum :change_type, { renewal: 1, update: 2 }, prefix: true
end
