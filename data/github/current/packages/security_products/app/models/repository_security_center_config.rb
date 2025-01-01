# typed: true
# frozen_string_literal: true

class RepositorySecurityCenterConfig < ApplicationRecord::Notify # rubocop:todo GitHub/DatabaseModelsShouldHaveTests
  extend GitHub::SimplePagination
  extend ActiveSupport::Concern

  belongs_to :repository
  belongs_to :owner,
    class_name: "User"
  belongs_to :business,
    class_name: "Business"

  has_many :repository_security_center_statuses,
    foreign_key: :repository_id,
    primary_key: :repository_id,
    inverse_of: :repository_security_center_config

  has_many :security_center_alert_severities,
    foreign_key: :repository_id,
    primary_key: :repository_id,
    inverse_of: :repository_security_center_config

  scope :with_owners_under_business, ->(business, orgs, include_emus: false) {
    if include_emus
      # Working with a business that does have enterprise users
      rel = where(business: business)

      org_rel = rel.where(owner_id: orgs, owner_type: "ORGANIZATION")
      user_rel = rel.where(owner_type: "USER")

      rel.and(org_rel.or(user_rel))
    else
      # Working with a business that does not have enterprise users
      where(owner_id: orgs, owner_type: "ORGANIZATION", business: business)
    end
  }

  def self.use_index(index)
    from("#{self.table_name} USE INDEX(#{index})")
  end
end
