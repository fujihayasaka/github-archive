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

      if user.feature_flag_enabled_or_raise?(:cap_filter_consider_outside_collabs) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        # for orgs to which a user is an outside collaborator, SAML enforcement should not be applied
        exempt_orgs = organizations.filter { |o| o.user_is_outside_collaborator?(user.id) }
        organizations = organizations.excluding(exempt_orgs)
      end

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
      filtered_org_ids = if filter_members
        saml_filter_debug_logging("filter_members is true", "saml_organization_ids_candidate")
        # Filter the organization ids to:
        # - Only the subset of organizations for which the user is a
        # member
        org_ids = if enable_outside_collab && user.feature_flag_enabled_or_raise?(:cap_filter_consider_outside_collabs) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
          user.authorizable_organization_ids
        else
          saml_filter_debug_logging("filter_members is false", "saml_organization_ids_candidate")
          user.organization_ids
        end

        # Since we are only interested in the organization that the user
        # is a member of, we can filter the organization list here and
        # possibly get a smaller list of organizations to check.
        all_org_ids & org_ids
      else
        all_org_ids
      end

      saml_filter_debug_logging("filtered_org_ids", "saml_organization_ids_candidate", {
        filtered_org_ids: filtered_org_ids,
      })

      biz_ids = []
      biz_ids = user.business_ids if filter_members
      saml_filter_debug_logging("user.business_ids", "saml_organization_ids_candidate", {
        business_ids: biz_ids,
      })

      # Set up an Organizations query that joins in:
      # - The Businesses that own the organization
      # - The Business' SAML provider (thus excluding any without providers)
      if user.guest_collaborator?
        saml_filter_debug_logging("user is user.guest_collaborator", "saml_organization_ids_candidate")
        biz_ids = [user.enterprise_managed_business.id]
      end

      saml_enforced_via_business_org_ids = []
      business_join_clause = <<-SQL.squish
        LEFT OUTER JOIN business_saml_providers
          ON business_saml_providers.business_id = business_organization_memberships.business_id
      SQL

      business_organizations = if biz_ids.any?
        Business::OrganizationMembership
          .joins(business_join_clause)
          .where(business_id: biz_ids)
          .where(organization_id: all_org_ids)
          .pluck(:organization_id, "business_saml_providers.business_id")
      elsif !filter_members
        Business::OrganizationMembership
          .joins(business_join_clause)
          .where(organization_id: all_org_ids)
          .pluck(:organization_id, "business_saml_providers.business_id")
      else
        []
      end
      saml_filter_debug_logging("business_organizations", "saml_organization_ids_candidate", {
        business_organizations: business_organizations
      })

      # Find only organizations with a SAML provider configured
      saml_enforced_via_business_org_ids = business_organizations.map { |id, business_id| id if business_id.present? }.compact.uniq
      saml_filter_debug_logging("saml_enforced_via_business_org_ids", "saml_organization_ids_candidate", {
        saml_enforced_via_business_org_ids: saml_enforced_via_business_org_ids,
      })

      # Find only organizations with a without SAML provider configured
      # those will have to be included if the plan does not match GitHub::Plan::BUSINESS_PLUS
      business_org_ids_no_saml = business_organizations.map { |id, business_id| id unless business_id.present? }.compact.uniq
      saml_filter_debug_logging("business_org_ids_no_saml", "saml_organization_ids_candidate", {
        business_org_ids_no_saml: business_org_ids_no_saml,
      })
      # Since we already have organizations with a SAML provider configured on a business
      # we can exclude those from the direct organizations query
      filtered_org_ids -= saml_enforced_via_business_org_ids
      saml_filter_debug_logging("filtered_org_ids", "saml_organization_ids_candidate", {
        filtered_org_ids: filtered_org_ids,
      })
      # no organizations without a business membership, no need to continue
      return saml_enforced_via_business_org_ids if filtered_org_ids.empty?

      saml_directly_enforced_org_ids = []
      if filtered_org_ids.any?
        # Set up an Organization's SAML provider query that joins in:
        # - The external identity matching the current user id
        external_identity = ExternalIdentity.select(:provider_id).where(provider_type: "Organization::SamlProvider", user_id: user.id)

        # Further filter the organization ids to:
        # - Only organizations with Business Plus Plan
        # - Only organizations where EITHER:
        #   - The SAML provider is enforced, OR
        #   - The user has an existing external identity mapping
        org_conditions = <<-SQL.squish
          (
            users.plan = :plan OR
            users.id IN (:business_org_ids)
          )
          AND organization_saml_providers.organization_id IN (:organization_ids)
          AND (
            organization_saml_providers.enforced = 1
            OR tmp_external_identities.provider_id IS NOT NULL
          )
        SQL
        # This uses the above clauses to grab all
        # organizations for which SAML is enforced due to being directly
        # enabled and enforced on the org itself.
        saml_directly_enforced_org_ids = Organization::SamlProvider
          .joins(:target)
          .joins(ExternalIdentity.sanitize_sql("LEFT JOIN (#{external_identity.to_sql}) AS tmp_external_identities ON tmp_external_identities.provider_id = organization_saml_providers.id"))
          .where(org_conditions, plan: GitHub::Plan::BUSINESS_PLUS, business_org_ids: business_org_ids_no_saml, organization_ids: filtered_org_ids, user_id: user.id)
          .pluck(:organization_id)
        saml_filter_debug_logging("saml_directly_enforced_org_ids", "saml_organization_ids_candidate", {
          saml_directly_enforced_org_ids: saml_directly_enforced_org_ids,
        })
        saml_directly_enforced_org_ids.union(saml_enforced_via_business_org_ids)
      end
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

    private_class_method def self.saml_filter_debug_logging(msg, function, options = {})
      return unless FeatureFlag.vexi.enabled?(:saml_filter_logging, default: false)
      GitHub.logger.info(
        msg,
        {
          "code.function": function,
          "gh.request_id": GitHub.context[:request_id],
          **options
        }
      )
    end
  end
end
