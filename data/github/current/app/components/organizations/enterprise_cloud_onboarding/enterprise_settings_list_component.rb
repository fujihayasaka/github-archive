# typed: strict
# frozen_string_literal: true

class Organizations::EnterpriseCloudOnboarding::EnterpriseSettingsListComponent < ApplicationComponent
  sig { returns(User) }
  attr_reader :user

  sig { returns(T.untyped) }
  attr_reader :system_arguments

  sig { params(user: User, system_arguments: T.untyped).void }
  def initialize(user:, **system_arguments)
    @user = user
    @system_arguments = system_arguments
  end

  private

  sig { returns(T::Boolean) }
  def render?
    return false if GitHub.single_or_multi_tenant_enterprise?

    eligible_organizations.any?
  end

  sig { returns(T::Array[::Organization]) }
  memoize def eligible_organizations
    user.owned_organizations.business_plus.select(&:eligible_for_upgrade_to_enterprise?)
  end
end
