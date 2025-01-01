# typed: true
# frozen_string_literal: true

module Repository::TwoFactorRequirementDependency
  extend T::Helpers
  requires_ancestor { Repository }

  # Public: Returns true if this repository's 2FA Authentication requirement
  #         (if any) can be met by the given PROSPECTIVE_MEMBER.
  #
  # prospective_member - a User
  #
  # Returns a Boolean.
  def two_factor_requirement_met_by?(prospective_member)
    return false if organization && !organization&.two_factor_requirement_met_by?(prospective_member)
    true
  end

  def async_two_factor_requirement_met_by?(prospective_member)
    self.async_organization.then do |organization|
      next Promise.resolve(true) unless organization
      next Promise.resolve(organization.async_two_factor_requirement_met_by?(prospective_member))
    end
  end

  # Public: Returns true if this repository's organization allows members without 2FA
  #
  # Returns a Boolean.
  def members_without_2fa_allowed?
    return false if organization && !organization&.members_without_2fa_allowed?
    true
  end

  def async_members_without_2fa_allowed?
    self.async_organization.then do |organization|
      next Promise.resolve(true) unless organization
      next Promise.resolve(organization.async_members_without_2fa_allowed?)
    end
  end

  # Public: Returns true if the provided user is using an insecure 2FA method
  #
  # prospective_member - a User
  #
  # Returns a Boolean.
  def disallowed_two_factor_method_used_by?(prospective_member)
    return true if organization && organization&.disallowed_two_factor_method_used_by?(prospective_member)
    false
  end
end
