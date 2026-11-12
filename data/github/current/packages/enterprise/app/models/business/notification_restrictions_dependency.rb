# typed: true
# frozen_string_literal: true

module Business::NotificationRestrictionsDependency
  extend ActiveSupport::Concern

  # The maximum number of `user_emails` rows a set of domains may match before the domain-driven
  # eligibility lookup is abandoned in favour of the member-driven one. See
  # `user_ids_with_email_in_domains`.
  DOMAIN_EMAIL_SCAN_LIMIT = 500_000

  # Public: The members of all enterprise organizations who do not have an email
  # address eligible to receive notifications when notifications restrictions are
  # enabled. Conditions for eligibility:
  #   - email address must be verified (if applicable - N/A in GHES/AE)
  #   - email address must from a verified or approved domain (domain can belong
  #     to the org, or to the parent enterprise)
  #
  # Returns a ActiveRecord::Relation<User>
  def members_without_eligible_email
    User.where(id: member_ids_without_eligible_email)
  end

  # Public: The members of all enterprise organizations who do not have an email
  # address eligible to receive notifications when notifications restrictions are
  # enabled. Conditions for eligibility:
  #   - email address must be verified (if applicable - N/A in GHES/AE)
  #   - email address must from a verified or approved domain (domain can belong
  #     to the org, or to the parent enterprise)
  #
  # Returns a GitHub::BatchedScope::BatchedScopeQuery
  def batched_members_without_eligible_email
    User.batched_scope(:id, values: member_ids_without_eligible_email)
  end

  # Public: The ids of members of all enterprise organizations who do not have an email
  # address eligible to receive notifications when notifications restrictions are
  # enabled. Conditions for eligibility:
  #   - email address must be verified (if applicable - N/A in GHES/AE)
  #   - email address must from a verified or approved domain (domain can belong
  #     to the org, or to the parent enterprise)
  #
  # Returns an Array of Integers
  def member_ids_without_eligible_email
    member_ids_without_eligible_email_hash.values.flatten.uniq
  end

  # Public: The number of members of all enterprise organizations who do not have an email
  # address eligible to receive notifications when notifications restrictions are
  # enabled. Conditions for eligibility:
  #   - email address must be verified (if applicable - N/A in GHES/AE)
  #   - email address must from a verified or approved domain (domain can belong
  #     to the org, or to the parent enterprise)
  #
  # Returns a Integer
  def members_without_eligible_email_count
    member_ids_without_eligible_email_hash.values.flatten.uniq.count
  end

  # Public: get the orgs that the user belongs to where notification restrictions are now enabled,
  # but the user won't receive notifications because they don't have an eligible email address.
  #
  # member - user we're looking at
  #
  # Array[Organization]
  def orgs_for_member_without_eligible_email(member)
    members_without_eligible_email_hash.keys.keep_if do |org|
      members_without_eligible_email_hash[org].include?(member)
    end
  end

  private

  # Private: return a Hash mapping this Business' organizations and their members who do not have
  # a verified email from a verified or approved domain
  #
  # Returns: Hash: { Organization => ActiveRecord::Relation<User> }
  def members_without_eligible_email_hash
    return @members_hash if defined?(@members_hash)

    enterprise_domains = T.unsafe(self).verifiable_domains.verified_or_approved
    org_domains = VerifiableDomain.includes(:owner).verified_or_approved.where(
      owner_type: "User",
      owner_id: T.unsafe(self).organization_ids
    ).group_by(&:owner)

    results = Hash.new { |h, k| h[k] = [] }
    @members_hash = if enterprise_domains.empty? && org_domains.empty?
      results
    else
      T.unsafe(self).organizations.each_with_object(results) do |organization|
        domains = enterprise_domains + org_domains[organization].to_a
        results[organization] = organization.members_without_eligible_email(domains).
          order(:id)
      end
    end
  end

  # Private: return a Hash mapping this Business' organizations and their members who do not have
  # a verified email from a verified or approved domain. Same as above but using ids instead of
  # objects.
  #
  # Returns: Hash: { Integer => Array<Integer> }
  def member_ids_without_eligible_email_hash
    return @member_ids_hash if defined?(@member_ids_hash)

    enterprise_domains = T.unsafe(self).verifiable_domains.verified_or_approved
    org_domains = VerifiableDomain.includes(:owner).verified_or_approved.where(
      owner_type: "User",
      owner_id: T.unsafe(self).organization_ids
    ).group_by(&:owner_id)

    results = Hash.new { |h, k| h[k] = [] }
    return @member_ids_hash = results if enterprise_domains.empty? && org_domains.empty?

    organization_ids = T.unsafe(self).organization_ids
    member_ids_by_org = organization_ids.index_with { [] }
    organization_and_member_ids = T.unsafe(self).business_org_abilities(org_ids: organization_ids) do |scope|
      scope.pluck(:subject_id, :actor_id)
    end
    if organization_and_member_ids.is_a?(ActiveRecord::Relation)
      organization_and_member_ids = organization_and_member_ids.pluck(:subject_id, :actor_id)
    end
    organization_and_member_ids.each do |organization_id, member_id|
      member_ids_by_org[organization_id] << member_id
    end
    member_ids_by_org.each_value(&:uniq!)

    # Enterprise domains are inherited by member orgs, so eligibility for them is resolved once
    # across every member rather than once per org. Anyone eligible here is eligible in every org.
    enterprise_eligible_ids = eligible_user_ids_for_domains(
      member_ids_by_org.values.flatten.uniq,
      enterprise_domains,
    )

    @member_ids_hash = member_ids_by_org.each_with_object(results) do |(org_id, member_ids), ids_by_org|
      ineligible_ids = member_ids - enterprise_eligible_ids

      # Only orgs owning their own domains need a second check, and only for the members that are
      # still ineligible after the enterprise-wide one.
      specific_domains = org_domains[org_id]
      if ineligible_ids.any? && specific_domains.present?
        ineligible_ids -= eligible_user_ids_for_domains(ineligible_ids, specific_domains)
      end

      ids_by_org[org_id] = ineligible_ids.sort
    end
  end

  # Private: The subset of the given User IDs that have an email address from one of the given
  # domains which is eligible to receive notifications.
  #
  # The lookup is domain-driven where possible. Matching on `normalized_domain` alone is served
  # entirely by the (normalized_domain, user_id) index on `user_emails`, so it costs a single
  # index-only range scan no matter how many members the enterprise has. Asking the question the
  # other way around - "for each member, do they have an eligible email?", as
  # `Organization#member_ids_without_eligible_email` does - costs an index lookup per member plus
  # a row read per matching email, which is what makes this time out for large enterprises.
  #
  # user_ids - Array of User IDs to check.
  # domains  - A collection of VerifiableDomains to match against.
  #
  # Returns an Array of Integer User IDs.
  def eligible_user_ids_for_domains(user_ids, domains)
    domain_names = domains.map(&:domain)
    return [] if user_ids.empty? || domain_names.empty?

    scanned_user_ids = user_ids_with_email_in_domains(domain_names)

    # Fall back to checking each member's own emails when the domains are too broad to scan.
    return user_ids_with_eligible_email_in_domains(user_ids, domain_names) if scanned_user_ids.nil?

    candidate_ids = user_ids & scanned_user_ids

    # `state` isn't part of the (normalized_domain, user_id) index, so it can't be filtered during
    # the scan without reading a row per matching email. Only the members that actually have an
    # email on one of the domains need their verification state checked.
    return candidate_ids if candidate_ids.empty? || !GitHub.email_verification_enabled?

    user_ids_with_eligible_email_in_domains(candidate_ids, domain_names)
  end

  # Private: The IDs of Users with an email address on one of the given domains, ignoring whether
  # that address is verified.
  #
  # Verified domains are DNS-proven, so they only ever cover an organization's own members. Approved
  # domains require no proof at all though, so an owner can approve a domain hosting private email
  # addresses (`gmail.com`, say). Scanning every email on a domain like that would cost far more
  # than the per-member lookup it is meant to replace, so the scan is abandoned once it matches
  # implausibly many emails.
  #
  # domain_names - Array of String domain names to match against.
  #
  # Returns an Array of Integer User IDs, or nil if the domains matched too many emails to scan.
  def user_ids_with_email_in_domains(domain_names)
    scope = UserEmail.where(normalized_domain: domain_names)
    return if T.unsafe(scope.limit(DOMAIN_EMAIL_SCAN_LIMIT + 1)).count > DOMAIN_EMAIL_SCAN_LIMIT

    T.unsafe(scope).pluck(:user_id)
  end

  # Private: The subset of the given User IDs with an email address on one of the given domains
  # that is eligible to receive notifications, looked up per User rather than per domain.
  #
  # user_ids     - Array of User IDs to check.
  # domain_names - Array of String domain names to match against.
  #
  # Returns an Array of Integer User IDs.
  def user_ids_with_eligible_email_in_domains(user_ids, domain_names)
    scope = UserEmail.where(normalized_domain: domain_names)
    scope = scope.where(state: "verified") if GitHub.email_verification_enabled?

    T.unsafe(scope.distinct).batched_scope(:user_id, values: user_ids).pluck(:user_id)
  end
end
