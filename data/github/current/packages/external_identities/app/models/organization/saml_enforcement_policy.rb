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
      # Set up an Organizations query that joins in:
      # - The Organization's SAML provider (thus excluding any without providers)
      # - The external identity mappings for the organization
      org_join_clause = <<-SQL.squish
        INNER JOIN organization_saml_providers
          ON organization_saml_providers.organization_id = users.id
        LEFT JOIN external_identities
          ON external_identities.provider_id = organization_saml_providers.id
            AND external_identities.provider_type = "Organization::SamlProvider"
      SQL

      # Filter the organizations to:
      # - Only the subset of organizations for which the user is a
      # member
      # - Only organizations where EITHER:
      #   - The SAML provider is enforced, OR
      #   - The user has an existing external identity mapping
      org_conditions = <<-SQL.squish
        users.id IN (:organization_ids)
        AND (
          organization_saml_providers.enforced = 1
          OR external_identities.user_id = :user_id
        )
      SQL

      org_ids = user.organization_ids

      # This uses the above JOIN and WHERE clauses to grab all
      # organizations for which SAML is enforced due to being directly
      # enabled and enforced on the org itself.
      saml_directly_enforced_org_ids = Organization.joins(org_join_clause)
        .where(org_conditions, organization_ids: org_ids, user_id: user.id)
        .distinct.pluck(:id)

      # Set up an Organizations query that joins in:
      # - The Businesses that own the organization
      # - The Business' SAML provider (thus excluding any without providers)
      biz_ids = user.business_ids

      if user.guest_collaborator?
        biz_ids = [user.enterprise_managed_business.id]
      end

      business_join_clause = <<-SQL.squish
        INNER JOIN business_organization_memberships
          ON business_organization_memberships.organization_id = users.id
        INNER JOIN businesses
          ON businesses.id = business_organization_memberships.business_id
        INNER JOIN business_saml_providers
          ON business_saml_providers.business_id = business_organization_memberships.business_id
      SQL

      # Return all organization ids where the user is a member of the owning business, either because:
      # - The user is a member of the org
      # - The user is a member of the business containing the org (i.e. an admin, billing manager, etc.)
      business_conditions = <<-SQL.squish
        businesses.id IN (:business_ids)
      SQL

      saml_enforced_via_business_org_ids = Organization
        .joins(business_join_clause)
        .where(business_conditions, business_ids: biz_ids)
        .pluck(:id)

      all_org_ids = saml_directly_enforced_org_ids.union(saml_enforced_via_business_org_ids)

      organizations.filter { |o| all_org_ids.include?(o.id) }
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
