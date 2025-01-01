# typed: strict
# frozen_string_literal: true

class Organizations::EnterpriseCloudOnboarding::EnterpriseAccountMigrationBannerComponent < ApplicationComponent
  sig { returns(::Organization) }
  attr_reader :organization

  sig { returns(T.nilable(User)) }
  attr_reader :user

  sig { params(organization: ::Organization, user: T.nilable(User)).void }
  def initialize(organization:, user:)
    @organization = organization
    @user = user
  end

  private

  sig { returns(T::Boolean) }
  def render?
    return false unless (current_user = user)
    return false unless organization.adminable_by?(current_user)
    return false unless organization.eligible_for_upgrade_to_enterprise?

    true
  end
end
