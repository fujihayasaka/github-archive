# typed: true
# frozen_string_literal: true

module User::TwoFactorRequirementDependency
  extend T::Helpers
  include GitHub::Memoizer
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
  # Returns a Boolean.
  def affiliated_with_organization?(org, include_collaboration: true)
    # abilities-based checks
    return true if org.direct_or_team_member?(self) || org.billing_manager?(self)
    return true if include_collaboration && org.user_is_outside_collaborator?(self.id)

    # user_role-based checks
    return true if OrganizationRole.assignments_for(actor: T.unsafe(self), org: org).any? ||
      OrganizationRole.repository_roles_for(actor: T.unsafe(self), org: org).any?

    false
  end

  # this method implements affiliated_with_organization? for N resources so it
  # can avoid N+1s when filtering organization targets for CAP.
  #
  # IMPORTANT - this does NOT check outside collaboratorship like the `affiliated_with_organization?` method above does with include_collaboration: true
  # _if_ we ever want to check outside collaboratorship here, we'll need to add some queries. However, as it stands today,
  # outside collaborators that do not satisfy 2FA requirements are booted from the org/enterprise entirely.
  #
  # IMPORTANT - this does NOT run user role checks like the `affiliated_with_organization?` method above.
  # The UserRole checks are still WIP, but we will need to account for them in the future.
  #
  # - organizations - an Enumerable of Organizations to be filtered
  #
  # Returns a subset of the input organizations for which the user (self) is affiliated.
  def filter_affiliated_organizations(organizations)
    if self.is_enterprise_managed? && self.enterprise_managed_business.oidc_enabled?
      all_org_ids = self.organization_ids
      return organizations.filter { |o| all_org_ids.include?(o.id) }
    end

    subject_type_to_org_ids_map = self.organization_ids_by_member_or_billing_manager_status
    org_ids = subject_type_to_org_ids_map[:member] | subject_type_to_org_ids_map[:billing_manager]
    member_or_billing_manager_org_ids = org_ids.uniq

    indirect_org_ids = if self.guest_collaborator?
      biz_ids = [self.enterprise_managed_business.id]
      Business::OrganizationMembership.where(business_id: biz_ids).pluck(:organization_id)
    else
      self.org_ids_via_business_membership
    end

    all_org_ids = member_or_billing_manager_org_ids.union(indirect_org_ids)
    all_org_ids_lookup = all_org_ids.index_with { true }
    organizations.filter { |o| all_org_ids_lookup[o.id] }
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

  def affiliation_disallows_sms_2fa?
    disallowed_methods = disallowed_two_factor_methods_from_affiliated_organizations.merge disallowed_two_factor_methods_from_affiliated_businesses
    disallowed_methods.include? :sms
  end

  # Public: All disallowed 2FA methods from affiliated organizations
  #
  # That is, a unique list of 2FA-requiring organizations with which the user is
  # affiliated. See #affiliated_organizations for the definition of affiliated.
  #
  # Returns an Array of Organizations
  def disallowed_two_factor_methods_from_affiliated_organizations
    disallowed_methods = Set.new
    affiliated_organizations.select do |org|
      disallowed_methods.merge org.get_two_factor_disallowed_methods
    end
    disallowed_methods
  end

  # Public: All disallowed 2FA methods from affiliated businesses.
  #
  # That is, a unique list of 2FA-requiring businesses with which the user is
  # affiliated. See #affiliated_businesses_as_administrator for the definition
  # of affiliated.
  #
  # Returns an Array of Business.
  def disallowed_two_factor_methods_from_affiliated_businesses
    disallowed_methods = Set.new
    businesses.select do |business|
      disallowed_methods.merge business.get_two_factor_disallowed_methods
    end
    disallowed_methods
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

  # Temporary - until outside collaborators can efficiently be handled w/ CAP,
  # they may not retain membership to orgs, without 2FA enabled
  # https://github.com/github/authorization/issues/4526
  def may_retain_affiliation_without_2fa?(org)
    return false if outside_collaborator_organizations.include?(org)

    org.members_without_2fa_allowed?
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

  def instrument_sudo_result(success, payload = {})
    if success
      instrument :sudo_challenge_success, two_factor_audit_context(payload)
    else
      instrument :sudo_challenge_failure, two_factor_audit_context(payload)
    end
  end

  def two_factor_audit_context(payload)
    payload.merge(
      user: login,
      actor: login,
      actor_id: id,
      user_id: id,
    )
  end

  # Public: Determines if a user's configured method(s) of 2FA are part of a given list of 2FA methods.
  # Valid methods are found in `Configurable::TwoFactorDisallowedMethods::METHOD_VALUES`
  #
  # Returns a Boolean
  def has_any_given_2fa_methods_configured?(methods)
    return false if methods&.empty?
    methods.each do |method|
      if method == :insecure
        return true if has_any_given_2fa_methods_configured? Configurable::TwoFactorDisallowedMethods::INSECURE_METHODS.to_a
      elsif method == :sms
        return true if two_factor_configured_with?(:sms) || two_factor_backup_sms_registration?
      elsif method == :totp
        return true if two_factor_configured_with? :app
      elsif method == :gh_mobile
        # We dont really have a way to check if the user has gh_mobile enabled for 2fa explicitly
        # If the user has 2FA enabled + a valid mobile session gh mobile can be offered as an option for 2FA
        # Even if we added a way to check for this, a user in 1 random org out of 100 that decided to disallow
        # mobile 2FA now stops that user from using mobile 2FA over all of GitHub.
        # This is a future problem as we arent allowing granular access to disallow certain 2FA methods yet,
        # but this is a problem that needs to be solved when that time comes.
      elsif method == :security_key
        return true if has_registered_security_key?
      elsif method == :passkey
        return true if has_registered_passkey?
      else
        Kernel.raise Configurable::TwoFactorDisallowedMethods::InvalidTwoFactorMethod, "Unhandled 2FA method in two_factor_satisfied: #{method}"
      end
    end

    false
  end

  # Public: Determines if a user's configured method(s) of 2FA are part of a given target's list of disallowed methods
  # Valid methods are found in `Configurable::TwoFactorDisallowedMethods::METHOD_VALUES`
  #
  # target - org/enterprise
  # known_disallowed_methods - the disallowed methods for the given target - pass to avoid config lookup
  #
  # Returns a Set of disallowed methods from the given target that the user has configured
  def disallowed_methods_configured(target, known_disallowed_methods: Set.new)
    return Set.new unless target.present?

    disallowed_methods = known_disallowed_methods.any? ? known_disallowed_methods : target.get_two_factor_disallowed_methods

    two_factor_methods_configured.intersection(disallowed_methods)
  end

  private

  # Determines if Two-Factor can be disabled because Conditional Access Policy Framework (CAP) is in place
  # - all orgs with 2FA enforced satisfy Organizatio#members_without_2fa_allowed?
  # - the user is not an admin nor billing manager of a 2FA enforced organization - we want to avoid a situation where the only admin/billing manager
  #   of the org looses access
  # - the user is not an owner / billing manager for a business (following same rational as above)
  def can_be_disabled_with_cap?
    requiring_orgs = affiliated_organizations_with_two_factor_requirement

    # remove this line after https://github.com/github/authorization/issues/4526
    return false if requiring_orgs.any? { |org| !may_retain_affiliation_without_2fa?(org) }

    requiring_orgs.map { |org| org.members_without_2fa_allowed? }.all? &&
    affiliated_organizations_with_roles.select { |org, roles| org.two_factor_requirement_enabled? && (roles.include?(:admin) || roles.include?(:billing_manager)) }.none? &&
      affiliated_businesses_with_two_factor_requirement.none?
  end

  # Returns all 2FA methods that a user has configured
  # Same logic as has_any_given_2fa_methods_configured? for checking configurations, but returns all methods configured
  # instead of a boolean about if _any_ given method is configured
  memoize def two_factor_methods_configured
    methods = Set.new

    methods << :sms if two_factor_configured_with?(:sms) || two_factor_backup_sms_registration?
    methods << :totp if two_factor_configured_with?(:app)
    # No way to currently check gh_mobile, this is a TODO for the future
    # methods << :gh_mobile if _____________
    methods << :security_key if has_registered_security_key?
    methods << :passkey if has_registered_passkey?

    methods
  end
end
