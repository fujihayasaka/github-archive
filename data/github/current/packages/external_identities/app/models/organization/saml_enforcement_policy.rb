# typed: true
# frozen_string_literal: true

class Organization
  class SamlEnforcementPolicy
    attr_reader :organization, :user
    alias_attribute :target, :organization

    def initialize(organization:, user:)
      @organization = organization
      @user = user
    end

    BATCH_SIZE = 5_000

    # this method implements the same as enforced? but for N resources so it
    # can be used to avoid N+1s
    #
    # - organizations - an Enumerable of Organizations to be filtered
    #
    # - user          - the user attempting to access resources
    #                   controlled by these organizations
    #                   (this is necessary to evaluate if they have a
    #                   mapped identity, which would require SAML
    #                   enforcement)
    #
    # Returns a subset of the input organizations for which SAML should be enforced.
    def self.filter_enforced(organizations, user)
      raise ArgumentError.new("user must not be nil") if user.nil?
      raise ArgumentError.new("organization argument must include only Organization instances") if organizations.any? { |o| !o.instance_of?(Organization) }

      if user.is_enterprise_managed? && user.enterprise_managed_business.oidc_enabled?
        all_org_ids = user.organization_ids
        return organizations.filter { |o| all_org_ids.include?(o.id) }
      end

      all_org_ids = saml_organization_ids(
        organizations.map(&:id),
        user,
        filter_members: true,
        enable_outside_collab: false)

      organizations.filter { |o| all_org_ids.include?(o.id) }
    end

    def self.saml_organization_ids(all_org_ids, user, filter_members: false, enable_outside_collab: true)
      # Split query implementation: avoid the complex LEFT JOINs by fetching data in separate queries.
      # This preserves the previous joined-query behavior while optimizing for cross-cluster support.

      filtered_org_ids = if filter_members
        all_org_ids & user.organization_ids
      else
        all_org_ids
      end

      biz_ids = if user.guest_collaborator?
        [user.enterprise_managed_business.id]
      elsif filter_members
        user.business_ids
      else
        []
      end

      saml_enforced_via_business_org_ids = Set.new
      business_org_ids_no_saml = Set.new

      # Split: fetch org memberships and SAML providers separately, then join in Ruby.
      org_memberships = if biz_ids.any?
        Business::OrganizationMembership
          .where(business_id: biz_ids)
          .batched_scope(:organization_id, values: all_org_ids, batch_size: BATCH_SIZE)
          .pluck(:business_id, :organization_id)
      elsif !filter_members
        Business::OrganizationMembership
          .batched_scope(:organization_id, values: all_org_ids, batch_size: BATCH_SIZE)
          .pluck(:business_id, :organization_id)
      else
        []
      end

      if org_memberships.any?
        # Query only the businesses mentioned in org_memberships, not all business SAML providers
        relevant_business_ids = org_memberships.map(&:first).uniq
        businesses_with_saml = Business::SamlProvider
          .batched_scope(:business_id, values: relevant_business_ids, batch_size: BATCH_SIZE)
          .pluck(:business_id)
          .to_set

        # Partition orgs by whether their owning business has SAML
        org_memberships.each do |business_id, org_id|
          if businesses_with_saml.include?(business_id)
            saml_enforced_via_business_org_ids << org_id
          else
            business_org_ids_no_saml << org_id
          end
        end
      end

      filtered_org_ids -= saml_enforced_via_business_org_ids.to_a

      # Skip if no organizations without business membership need checking
      return saml_enforced_via_business_org_ids.to_a if filtered_org_ids.empty?

      # Check for direct organization SAML enforcement
      if filtered_org_ids.any?
        # Fetch all orgs that are eligible for SAML enforcement based on plan and business membership
        # Only include business_org_ids_no_saml that are also in filtered_org_ids,
        # matching the joined behavior which gates the direct check on filtered_org_ids.
        relevant_business_org_ids_no_saml = business_org_ids_no_saml.to_a & filtered_org_ids
        direct_org_ids_only = filtered_org_ids - relevant_business_org_ids_no_saml
        plan_eligible_org_ids = Organization
          .where(plan: GitHub::Plan::BUSINESS_PLUS)
          .batched_scope(:id, values: direct_org_ids_only, batch_size: BATCH_SIZE)
          .pluck(:id)
          .to_set
        sso_ready_org_ids = plan_eligible_org_ids | relevant_business_org_ids_no_saml

        # Fetch all SAML providers for these orgs, including whether they are enforced or not
        org_saml_providers = Organization::SamlProvider
          .batched_scope(:organization_id, values: sso_ready_org_ids, batch_size: BATCH_SIZE)
          .pluck(:organization_id, :id, :enforced)

        # Fetch all provider ids where enforced is false
        enabled_provider_ids = org_saml_providers.select { |_, _, enforced| !enforced }.map(&:second).to_set

        # Fetch all provider ids where the user has an external identity
        user_external_identity_provider_ids = ExternalIdentity
          .where(provider_type: "Organization::SamlProvider", user_id: user.id)
          .batched_scope(:provider_id, values: enabled_provider_ids.to_a, batch_size: BATCH_SIZE)
          .pluck(:provider_id)
          .to_set

        # Fetch all org ids from org_saml_providers where the provider is either enforced
        # or the provider id is in user_external_identity_provider_ids
        # A user needs to comply with SAML if they have an external identity or the provider is enforced
        saml_directly_enforced_org_ids = org_saml_providers.select { |_, provider_id, enforced| enforced || user_external_identity_provider_ids.include?(provider_id) }.map(&:first).to_set
        return (saml_directly_enforced_org_ids | saml_enforced_via_business_org_ids).to_a
      end

      saml_enforced_via_business_org_ids.to_a
    end

    def enforced?
      return @enforced if defined?(@enforced)
      @enforced = calculate_enforced
    end

    private

    def calculate_enforced
      return false unless @organization && @user
      provider_owner = @organization.external_identity_session_owner
      if provider_owner.is_a?(Business)
        return Business::SamlEnforcementPolicy.new(business: provider_owner, organization: @organization, user: @user).enforced?
      end
      return false unless @organization.saml_sso_enabled?
      return false unless @organization.member?(@user)
      return false if     @organization.user_is_outside_collaborator?(@user.id)
      return false unless @organization.external_identity_session_owner.saml_sso_enforced? ||
                          @organization.saml_provider.external_identities.exists?(user_id: @user.id)

      true
    end
  end
end
