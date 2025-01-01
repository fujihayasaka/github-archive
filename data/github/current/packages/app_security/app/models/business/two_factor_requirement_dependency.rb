# typed: true
# frozen_string_literal: true

module Business::TwoFactorRequirementDependency
  extend T::Helpers
  requires_ancestor { Business }

  # Public: Business owners with 2fa disabled.
  #
  # Returns an ActiveRecord::Relation for User.
  def owners_with_two_factor_disabled
    owners.two_factor_disabled
  end

  # Public: Business organization direct members with 2fa disabled.
  #
  # Returns an ActiveRecord::Relation for User.
  def members_with_two_factor_disabled
    organization_members.two_factor_disabled
  end

  # Public: Business outside collaborators with 2fa disabled.
  #
  # Returns an ActiveRecord::Relation for User.
  def outside_collaborators_with_two_factor_disabled
    outside_collaborators.two_factor_disabled
  end

  # Public: Business billing managers with 2fa disabled.
  #
  # Returns an ActiveRecord::Relation for User.
  def billing_managers_with_two_factor_disabled
    billing_managers.two_factor_disabled
  end

  # Public: Affiliated users with 2FA disabled
  #
  # Returns an ActiveRecord::Relation for User.
  def affiliated_users_with_two_factor_disabled
    user_ids = admin_and_organization_member_ids.concat(outside_collaborator_ids)
    User.where(id: user_ids).two_factor_disabled
  end

  # Public: Affiliated users with 2FA enabled
  #
  # Returns an ActiveRecord::Relation for User.
  def affiliated_users_with_two_factor_enabled
    user_ids = admin_and_organization_member_ids.concat(outside_collaborator_ids)
    User.where(id: user_ids).two_factor_enabled
  end

  # Public: Does this business need confirmation to enable the two factor
  # requirement across all organizations?
  #
  # Returns a Boolean.
  def affiliated_users_with_two_factor_disabled_exist?
    return true if affiliated_users_with_two_factor_disabled.exists?

    false
  end

  # Public: Can the two factor requirement be enabled for this business?
  #
  # At least one admin in the business must have two factor authentication
  # enabled for the two factor requirement be enabled for this business.
  #
  # Returns a Boolean.
  def can_two_factor_requirement_be_enabled?
    owners.any?(&:two_factor_authentication_enabled?)
  end

  # Public: Is the two factor requirement currently being updated?
  #
  # Returns a Boolean.
  def updating_two_factor_requirement?
    return false unless enforce_two_factor_requirement_job_status.present?

    !enforce_two_factor_requirement_job_status.finished?
  end

  # Public: The JobStatus for the two factor requirement enforcement job.
  #
  # Returns a JobStatus or nil.
  def enforce_two_factor_requirement_job_status
    @enforce_two_factor_requirement_job_status ||= \
      EnforceTwoFactorRequirementOnBusinessJob.status(self)
  end

  # Public: Get the Organizations that can or cannot enable the
  # two-factor authentication requirement.
  #
  # can_enable_two_factor - Required Boolean indicating whether to return those orgs
  #   that can (true) or cannot (false) enable the two-factor authentication requirement.
  # orgs - Optional ActiveRecord::Relation if this method should apply to an existing
  #   collection of Organizations. Defaults to Business#organizations.
  #
  # Returns ActiveRecord::Relation.
  def organizations_can_enable_two_factor_requirement(can_enable_two_factor, orgs: organizations)
    org_admins = Hash.new { |h, k| h[k] = [] }
    Ability.where(
      subject_id: orgs.ids, subject_type: "Organization",
      actor_type: "User", priority: Ability.priorities[:direct],
      action: Ability.actions[:admin]
    ).pluck(:subject_id, :actor_id).each do |org_id, admin_id|
      org_admins[org_id] << admin_id
    end

    # Optimization to not have to check all organizations individually
    all_admin_ids = org_admins.values.flatten
    all_admin_2fa_scope = TwoFactorCredential.where(user_id: all_admin_ids)

    if all_admin_2fa_scope.count == all_admin_ids.size
      if can_enable_two_factor
        return orgs
      else
        return orgs.none
      end
    end

    # Grab all admin ids so we can intersect them with the per org admins
    all_admin_ids_with_2fa = all_admin_2fa_scope.pluck(:user_id)

    orgs_2fa_allowed = []
    org_admins.each do |org_id, admin_ids|
      if (all_admin_ids_with_2fa & admin_ids).any?
        orgs_2fa_allowed << org_id
      end
    end

    if can_enable_two_factor
      orgs.where(id: orgs_2fa_allowed)
    else
      orgs.where.not(id: orgs_2fa_allowed)
    end
  end

  # Public: Is two factor enforcement enabled for the business?
  #
  # Returns a Boolen
  def two_factor_cap_enforcement_enabled?
    T.bind(self, Business)
    GitHub.flipper[:two_factor_cap_enforcement].enabled?(self)
  end

  # Public: Are members without 2FA allowed to join the business? This can
  # only be true if the org has 2FA enforcement enabled already
  #
  # Returns a Boolen
  def members_without_2fa_allowed?
    T.bind(self, Business)
    return false unless two_factor_cap_enforcement_enabled?
    GitHub.flipper[:members_without_2fa_allowed].enabled?(self)
  end
end
