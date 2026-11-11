# typed: true
# frozen_string_literal: true

class Billing::SalesforceAccount < ApplicationRecord::Domain::Users
  has_one :business
  validates :salesforce_id, presence: true, uniqueness: true

  def salesforce_account_link
    "https://github.lightning.force.com/#{salesforce_id}"
  end
end
