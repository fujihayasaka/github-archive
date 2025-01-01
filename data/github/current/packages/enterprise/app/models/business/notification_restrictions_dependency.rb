# typed: true
# frozen_string_literal: true

module Business::NotificationRestrictionsDependency
  extend ActiveSupport::Concern

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
    @member_ids_hash = if enterprise_domains.empty? && org_domains.empty?
      results
    else
      T.unsafe(self).organizations.each_with_object(results) do |organization|
        domains = enterprise_domains + org_domains[T.must(organization.id)].to_a
        results[organization.id] = organization.member_ids_without_eligible_email(domains).sort
      end
    end
  end
end
