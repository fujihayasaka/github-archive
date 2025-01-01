# typed: strict
# frozen_string_literal: true

class Onboarding::Organizations::AdvancedSecurity::EnterpriseProtectedComponent < ApplicationComponent
  extend T::Sig

  sig { returns(T.nilable(Business)) }
  attr_reader :business

  sig { returns(User) }
  attr_reader :user

  sig { params(business: T.nilable(Business), user: User).void }
  def initialize(business:, user:)
    @business = business
    @user = user
  end

  sig { returns(T::Boolean) }
  def render?
    business.present?
  end

  sig { returns(T::Boolean) }
  memoize def can_manage_business?
    return false unless b = @business
    b.adminable_by?(user)
  end

  sig { returns(T::Boolean) }
  memoize def show_buy_button?
    return false unless b = @business
    return false unless can_manage_business?
    return false unless b.eligible_for_self_serve_advanced_security?(skip_shared_checks: true)
    true
  end
end
