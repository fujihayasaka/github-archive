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

  # Public: Business owners with 2fa enabled.
  #
  # Returns an ActiveRecord::Relation for User.
  def owners_with_two_factor_enabled
    owners.two_factor_enabled
  end

  # Public: Business organization direct members with 2fa disabled.
  #
  # Returns an ActiveRecord::Relation for User.
  def members_with_two_factor_disabled
    organization_members.two_factor_disabled
  end

  # Public: Business organization direct members with 2fa enabled.
  #
  # Returns an ActiveRecord::Relation for User.
  def members_with_two_factor_enabled
    organization_members.two_factor_enabled
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

  # Public: Business billing managers with 2fa enabled.
  #
  # Returns an ActiveRecord::Relation for User.
  def billing_managers_with_two_factor_enabled
    billing_managers.two_factor_enabled
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

  # Public: Affiliated outside collaborators with 2FA disabled
  # Remove after https://github.com/github/authorization/issues/4526
  #
  # Returns an ActiveRecord::Relation for User.
  def affiliated_outside_collaborators_with_two_factor_disabled
    user_ids = outside_collaborator_ids
    User.where(id: user_ids).two_factor_disabled
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

  # Public: Disables the 2fa requirement for the business.
  def disable_two_factor_requirement(actor:, log_event: false)
    disabled_2fa = disable_two_factor_required(actor: actor, log_event: log_event)

    clear_disallowed_two_factor_methods(actor: actor, log_event: insecure_two_factor_methods_disallowed?)

    disabled_2fa
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

  def organizations_two_factor_policy_filter(policy, orgs: organizations)
    return orgs if policy.nil?

    orgs_2fa_enabled = orgs.select { |org| org.two_factor_requirement_enabled? }.pluck(:id)

    if policy == "enabled"
      return orgs.where(id: orgs_2fa_enabled)
    elsif policy == "disabled"
      return orgs.where.not(id: orgs_2fa_enabled)
    end

    orgs.none
  end

  def number_of_orgs_with_two_factor_requirement_disabled
    disabled_2fa_orgs = organizations.select { |org| !org.two_factor_requirement_enabled? }

    disabled_2fa_orgs.count
  end

  # Public: Is two factor enforcement enabled for the business?
  #
  # Returns a Boolen
  def two_factor_cap_enforcement_enabled?
    T.bind(self, Business)
    GitHub.tracer.in_span("Business#two_factor_cap_enforcement_enabled?") do |_span|
      self.feature_enabled?(:two_factor_cap_enforcement)
    end
  end

  # Public: Are members without 2FA allowed to join the business? This can
  # only be true if the org has 2FA enforcement enabled already
  #
  # Returns a Boolen
  def members_without_2fa_allowed?
    T.bind(self, Business)
    return false unless two_factor_cap_enforcement_enabled?
    self.feature_enabled?(:members_without_2fa_allowed)
  end

  # Public: Is the two factor methods restriction feature available for the business?
  #
  # Returns a Boolen
  def can_disallow_two_factor_methods?
    T.bind(self, Business)
    return false unless members_without_2fa_allowed?
    self.feature_enabled?(:disallow_two_factor_methods)
  end

  # Method exclusively for 2FA CAP policy to invoke, checking CAP enforcement of disallowed methods compared to UI feature allowing changes
  def enforce_two_factor_methods_policy?
    T.bind(self, Business)
    self.feature_enabled?(:enforce_disallow_two_factor_methods)
  end

  def disallow_insecure_two_factor_methods(actor:)
    T.bind(self, Business)
    EnforceTwoFactorRequirementOnBusinessJob.perform_later(self, actor, disallowed_methods: [Configurable::TwoFactorDisallowedMethods::INSECURE])
  end
end
