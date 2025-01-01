# typed: true
# frozen_string_literal: true

module Codespaces
  class VirtualNetwork < ApplicationRecord::Domain::Users
    belongs_to :business

    validates :subscription_name, presence: true
    validates :subscription_id, presence: true
    validates :virtual_network_name, presence: true
    validates :subnet_name, presence: true
    validates :subnet_id, presence: true, uniqueness: {
      scope: :business_id,
      message: "has already been registered under this enterprise"
    }

    scope :for_business, ->(business) { where(business_id: business.id) }
  end
end
