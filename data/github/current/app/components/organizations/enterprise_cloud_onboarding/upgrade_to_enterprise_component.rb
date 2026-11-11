# typed: strict
# frozen_string_literal: true

class Organizations::EnterpriseCloudOnboarding::UpgradeToEnterpriseComponent < ApplicationComponent
  sig { params(organization: ::Organization).void }
  def initialize(organization:)
    @organization = organization
  end

  private

  sig { returns(::Organization) }
  attr_reader :organization

  sig { returns(T::Boolean) }
  def render?
    return false unless organization.adminable_by?(current_user)
    organization.eligible_for_upgrade_to_enterprise?
  end
end
