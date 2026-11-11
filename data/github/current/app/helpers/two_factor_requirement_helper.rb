# typed: true
# frozen_string_literal: true

module TwoFactorRequirementHelper
  def two_factor_enabled?(user)
    return false unless user
    user.two_factor_authentication_enabled?
  end

  def active_account_two_factor_requirement?(user)
    return false unless user
    return false if two_factor_enabled?(user)
    user.in_account_2fa_requirement_required_state?
  end

  def pending_account_two_factor_requirement?(user)
    return false unless user
    return false if two_factor_enabled?(user)
    !user.in_account_2fa_requirement_required_state? && user.has_forthcoming_account_two_factor_requirement?
  end

  def account_two_factor_required_by_date(user)
    return nil unless user
    return nil if two_factor_enabled?(user)
    return nil unless user.has_forthcoming_account_two_factor_requirement?
    user.two_factor_requirement_metadata.required_by.utc
  end
end
