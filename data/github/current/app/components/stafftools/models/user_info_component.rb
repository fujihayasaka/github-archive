# typed: true
# frozen_string_literal: true

class Stafftools::Models::UserInfoComponent < ApplicationComponent
  sig { params(user: T.any(User, Organization)).void }
  def initialize(user:)
    @user = user
  end

  private

  sig { returns T.any(User, Organization) }
  attr_reader :user

  sig { returns T.nilable(T::Boolean) }
  def render?
    return false unless GitHub.models_enabled? && logged_in?
    if organization
      true
    else
      access_result = with_database_error_fallback(fallback: nil) { self.access_result }
      !access_result.nil?
    end
  end

  sig { returns T.nilable(Organization) }
  memoize def organization
    if user.organization?
      T.cast(user, Organization)
    end
  end

  sig { returns GitHubModels::PlaygroundAccessResult }
  memoize def access_result
    GitHubModels::PlaygroundAccessResult.for(user)
  end

  sig { returns T::Boolean }
  def has_models_access?
    access_result.accessible?
  end

  sig { returns T::Boolean }
  def models_enabled?
    organization = self.organization
    return false unless organization
    with_database_error_fallback(fallback: false) do
      GitHubModels::OrganizationAccessPolicy.new(org: organization).models_enabled_for_org?
    end
  end

  sig { returns T.nilable(String) }
  def access_reason
    reason = access_result.reason
    return unless reason
    reason.to_s.humanize
  end

  sig { returns T::Boolean }
  def models_billing_enabled?
    user.models_billing_enabled?
  end

  sig { returns Integer }
  memoize def total_custom_models
    organization&.custom_models&.count || 0
  end
end
