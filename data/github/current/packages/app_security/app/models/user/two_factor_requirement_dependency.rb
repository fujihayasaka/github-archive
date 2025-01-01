# typed: true
# frozen_string_literal: true

module User::TwoFactorRequirementDependency
  extend T::Helpers
  requires_ancestor { User }

  # Public: Returns true.
  #
  # prospective_member - a User
  #
  # Returns a Boolean.
  def two_factor_requirement_met_by?(prospective_member)
    true
  end

  # Public: Returns true if User SELF is affiliated with Organization ORG
  #   i.e. if any of the following conditions are met:
  #   - the user is a direct member of ORG
  #   - the user is an outside collaborator on any of ORG's private repositories
  #     (or forks thereof)
  #   - the user is a billing manager for ORG
  #
  # If user_org_affiliation_redefine FF is enabled, we compare a more inclusive abilities check to future-proof against association types.
  # Instead of checking for only specific types of relations to define affiliation, we check any possible association -
  # to org itself, to org's business, to any repos under the org.
  # As of July 2024, this is not effectively different from the previous implementation, but it will better handle
  # future affiliation types.
  #
  # Returns a Boolean.
  def affiliated_with_organization?(org)
    if org.feature_enabled?(:user_org_affiliation_redefine)
      affiliated_with_organization_candidate?(org)
    else
      science "affiliated_with_organization" do |e|
        e.use { affiliated_with_organization_original?(org) }
        e.try { affiliated_with_organization_candidate?(org) }
      end
    end
  end

  def affiliated_with_organization_original?(org)
    org.direct_or_team_member?(self) ||
      org.user_is_outside_collaborator?(self.id) ||
      org.billing_manager?(self)
  end

  def affiliated_with_organization_candidate?(org)
    # abilities-based checks
    return true if org.direct_or_team_member?(self) ||
      org.user_is_outside_collaborator?(self.id) ||
      org.billing_manager?(self)

    # user_role-based checks
    return true if OrganizationRole.assignments_for(actor: T.unsafe(self), org: org).any? ||
      OrganizationRole.repository_roles_for(actor: T.unsafe(self), org: org).any?

    false
  end

  def two_factor_lock_key
    "user:#{self.id}:two_factor_locked"
  end

  def two_factor_locked?
    GitHub.dogstats.increment("authn_kv", tags: ["action:read", "callsite:2fa_requirement_dependency"])
    GitHub::Authentication::KV.store.get(two_factor_lock_key).value { nil } == "true"
  end

  def lock_two_factor
    key = two_factor_lock_key
    begin
      GitHub.dogstats.increment("authn_kv", tags: ["action:write", "callsite:2fa_requirement_dependency"])
      kv_success = GitHub::Authentication::KV.store.try_set(key, "true", expires: 1.minute.from_now)
      unless kv_success
        GitHub.dogstats.increment("kv_unavailable", tags: { service_owner: :account_login, callsite: :org_invite_lock_two_factor, action: :set })
      end

      yield if block_given?
    ensure
      begin
        GitHub.dogstats.increment("authn_kv", tags: ["action:delete", "callsite:2fa_requirement_dependency"])
        GitHub::Authentication::KV.store.del(key)
      rescue GitHub::KV::UnavailableError
        GitHub.dogstats.increment("kv_unavailable", tags: { service_owner: :account_login, callsite: :org_invite_lock_two_factor, action: :del })
      end
    end
  end

  # Public: Returns true if 2FA can be disabled for this user,
  #   i.e. if all of the following conditions are met:
  #   - the user has 2FA enabled
  #   - the user does not have a 2FA requirement on their account
  #   - the user does not have a 2FA requirement inherited from an associated org/business
  #
  # Returns a Boolean.
  def two_factor_auth_can_be_disabled?
    return false unless two_factor_authentication_enabled?
    return false if self.in_account_2fa_requirement_required_state?
    return false if inherited_two_factor_required?

    true
  end

  # Public: Returns true if 2FA can be disabled by staff for this user,
  #   NOT equivalent to user definition of two_factor_auth_can_be_disabled - staff can disable 2FA for users
  #   who have a requirement only at the account level
  def two_factor_auth_can_be_disabled_by_staff?
    two_factor_authentication_enabled? && !inherited_two_factor_required?
  end

  # Public: Returns true if user meets any of the following criteria:
  #   - the user is affiliated with any orgs that require 2FA,
  #     where 'affiliated' denotes being a member, owner, or manager on an org,
  #     or a collaborator on an org's private repositories or any forks thereof
  #   - the user is affiliated with any enterprise accounts that require
  #     2FA, where 'affiliated' denotes being an administrator of the enterprise
  #     account.
  def inherited_two_factor_required?
    return true if two_factor_locked?
    return false if can_be_disabled_with_cap?
    affiliated_organizations_with_two_factor_requirement.any? ||
      affiliated_businesses_with_two_factor_requirement.any?
  end

  # Public: All affiliated organizations that require two-factor authentication
  #
  # That is, a unique list of 2FA-requiring organizations with which the user is
  # affiliated. See #affiliated_organizations for the definition of affiliated.
  #
  # Returns an Array of Organizations
  def affiliated_organizations_with_two_factor_requirement
    affiliated_organizations.select { |org| org.two_factor_requirement_enabled? }
  end

  # Public: All businesses with which the user is affiliated as an administrator
  # that require two-factor authentication.
  #
  # That is, a unique list of 2FA-requiring businesses with which the user is
  # affiliated. See #affiliated_businesses_as_administrator for the definition
  # of affiliated.
  #
  # Returns an Array of Business.
  def affiliated_businesses_with_two_factor_requirement
    affiliated_businesses_as_administrator.select { |business| business.two_factor_requirement_enabled? }
  end

  # Public: All affiliated organizations and the access type this user has to
  # each organization
  #
  # That is, a unique list of organizations with which the user is affiliated,
  # where 'affiliated' denotes being either:
  #  - a member or owner of the org
  #  - a billing manager (not necessarily a member) of the org
  #  - an outside (i.e., not an org member) collaborator on any public or
  #    private org owned repositories
  #  - an outside collaborator on a fork of any of the org's private repos
  #
  # Returns a Hash, where the key is the Organization, and the value is an
  # array of access privileges this user has to that Organization
  # :access can be one or more of [:admin, :member, :billing_manager, :outside_collaborator]
  # exception: :admin overrides :member, so those two will never be combined
  def affiliated_organizations_with_roles
    orgs_with_access_hash = Hash.new { |h, k| h[k] = [] }
    owned_organizations.each { |org| orgs_with_access_hash[org] << :admin }
    organizations.each { |org| orgs_with_access_hash[org] << :member if orgs_with_access_hash[org].empty? }
    billing_manager_organizations.each { |org| orgs_with_access_hash[org] << :billing_manager }
    outside_collaborator_organizations.each { |org| orgs_with_access_hash[org] << :outside_collaborator }
    orgs_with_access_hash
  end

  # Public: an array of all the affiliated organizations for this user
  #
  # includes organizations the user is a member of, is a billing manager
  # (not necessarily a member), or an outside collaborator
  #
  # Returns an Array of Organizations
  def affiliated_organizations
    affiliated_organizations_with_roles.keys
  end

  # Public: Returns the businesses with which the user is affiliated as
  # an administrator (owner or billing manager).
  #
  # Returns an ActiveRecord::Relation.
  def affiliated_businesses_as_administrator
    owner_affiliations = businesses(membership_type: :admin)
    billing_manager_affiliations = businesses(membership_type: :billing_manager)
    owner_affiliations.or(billing_manager_affiliations)
  end

  # Public: Returns all organizations affiliated with through outside
  # collaboratorship -- that is, where SELF is a member of a repo owned by the
  # organization but is not a member of the organization itself.
  #
  # Returns an ActiveRecord::Relation
  def outside_collaborator_organizations
    repository_ids = Authorization.service.subject_ids(actor: self, subject_type: "Repository")

    outside_collaborator_organization_ids = \
      Repository
        .where.not(organization_id: nil)
        .where(id: repository_ids)
        .active
        .distinct
        .pluck(:organization_id)

    if outside_collaborator_organization_ids.any?
      outside_collaborator_organization_ids -= organization_ids
    end

    if outside_collaborator_organization_ids.any?
      Organization.where(id: outside_collaborator_organization_ids)
    else
      Organization.none
    end
  end

  # Public: A list of SELF's roles on the given organization.
  #
  # Returns an Array of Symbols
  def abilities_on_organization(org)
    Organization::Role.new(org, self).types
  end

  def instrument_two_factor_recovery_codes_viewed(payload = {})
    instrument :two_factor_recovery_codes_viewed, two_factor_audit_context(payload)
  end

  def instrument_two_factor_recovery_codes_downloaded(payload = {})
    instrument :two_factor_recovery_codes_downloaded, two_factor_audit_context(payload)
  end

  def instrument_two_factor_recovery_codes_printed(payload = {})
    instrument :two_factor_recovery_codes_printed, two_factor_audit_context(payload)
  end

  def instrument_two_factor_requested(payload = {})
    instrument :two_factor_requested, two_factor_audit_context(payload)
  end

  def instrument_two_factor_recover(payload = {})
    instrument :two_factor_recover, two_factor_audit_context(payload)
  end

  def instrument_two_factor_challenge_success(payload = {})
    instrument :two_factor_challenge_success, two_factor_audit_context(payload)
  end

  def instrument_two_factor_challenge_failure(payload = {})
    instrument :two_factor_challenge_failure, two_factor_audit_context(payload)
  end

  def two_factor_audit_context(payload)
    payload.merge(
      user: login,
      actor: login,
      actor_id: id,
      user_id: id,
    )
  end

  private

  # Determines if Two-Factor can be disabled because Conditional Access Policy Framework (CAP) is in place
  # - all orgs with 2FA enforced satisfy Organizatio#members_without_2fa_allowed?
  # - the user is not an admin nor billing manager of a 2FA enforced organization - we want to avoid a situation where the only admin/billing manager
  #   of the org looses access
  # - the user is not an owner / billing manager for a business (following same rational as above)
  def can_be_disabled_with_cap?
    affiliated_organizations_with_two_factor_requirement.map { |org| org.members_without_2fa_allowed? }.all? &&
    affiliated_organizations_with_roles.select { |org, roles| org.two_factor_requirement_enabled? && (roles.include?(:admin) || roles.include?(:billing_manager)) }.none? &&
      affiliated_businesses_with_two_factor_requirement.none?
  end
end
