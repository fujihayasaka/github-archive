# typed: strict
# frozen_string_literal: true

class Billing::CreditCheck < ApplicationRecord::Domain::Billing

  belongs_to :customer

  enum :status, { pending_review: 0, approved: 1, rejected: 2 }

  validates :customer_id, presence: true, uniqueness: true
  validates :request_id, presence: true
  validates :status, presence: true, inclusion: { in: statuses.keys }
end
