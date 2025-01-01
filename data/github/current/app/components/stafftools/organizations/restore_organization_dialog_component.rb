# typed: true
# frozen_string_literal: true

class Stafftools::Organizations::RestoreOrganizationDialogComponent < ApplicationComponent
  sig { returns Organization }
  attr_reader :organization

  sig { returns T.nilable(Business) }
  attr_reader :business

  sig { returns String }
  attr_reader :return_to

  def initialize(organization:, business: nil, return_to:)
    @organization = organization
    @business = business
    @return_to = return_to
  end

  private

  sig { returns(T::Boolean) }
  def render?
    return false if GitHub.single_business_environment?
    return false if organization.belongs_to_a_soft_deleted_business?
    true
  end
end
