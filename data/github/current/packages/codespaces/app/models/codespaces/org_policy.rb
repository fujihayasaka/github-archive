# typed: true
# frozen_string_literal: true

module Codespaces
  class OrgPolicy
    DEFAULT_ROLE_GRANTER = Permissions::Granters::RoleGranter
    DEFAULT_AUTHORIZER = Permissions::Enforcer
    CODESPACE_ORG_CREATOR_ROLE = "codespace_org_creator"

    include GitHub::Memoizer

    class RoleGranterError < StandardError; end

    attr_reader :user, :org, :repo

    # known_org_relationship is one of [:none, :member, :collaborator].
    # When not :none, checking of the user's association to the org is skipped.
    def initialize(user:, org:, repo: nil, known_org_relationship: :none)
      raise ArgumentError, "Invalid known_org_relationship" unless [:none, :member, :collaborator].any?(known_org_relationship)
      raise ArgumentError, "A repo cannot be provided unless known_org_relationship is :none." if repo && known_org_relationship != :none

      @user = user
      @org = org
      @repo = repo
      @known_org_relationship = known_org_relationship
    end

    # Is the user authorized to bill codespaces to the org?
    #
    # This takes into consideration feature flags and org settings but *not*
    # current billing state, e.g., whether they're past their entitlement.
    def async_can_bill?
      @can_bill_promise ||= case
      when !org.codespaces_feature_enabled? then Promise.resolve(false)
      when org.plan.legacy? then Promise.resolve(false)
      when org.codespaces_access_disabled? then Promise.resolve(false)
      when org.codespaces_ownership_set_to_user? then Promise.resolve(false)
      when !member_or_collaborator? then Promise.resolve(false)
      when limit_to_users? then Promise.resolve(true)
      when limit_to_users_and_collaborators? then Promise.resolve(true)
      when !org.limits_organizations_codespaces_to_selected_users? then Promise.resolve(false)
      else
        Platform::Loaders::Permissions::BatchAuthorize.load(
          action: :write_org_codespace,
          actor: user,
          subject: org
        ).then { |decision| decision.allow? }
      end
    end

    def async_can_use_codespaces?
      # Can always use codespaces on public org-owned repositories.
      return Promise.resolve(true) if repo&.public?

      # The OrganizationCodespacesUserLimit configurable now controls whether codespaces can be used at all.
      if org.codespaces_access_disabled?
        Promise.resolve(false)
      elsif org.limit_organization_codespaces_to_users_and_collaborators?
        Promise.resolve(member_or_collaborator?)
      elsif org.limit_organization_codespaces_to_users?
        Promise.resolve(member?)
      elsif org.limits_organizations_codespaces_to_selected_users?
        Platform::Loaders::Permissions::BatchAuthorize.load(
          action: :write_org_codespace,
          actor: user,
          subject: org
        ).then { |decision| decision.allow? }
      else
        # Invalid setting...
        Promise.resolve(false)
      end
    end

    # Whether org admins can enable the codespaces setting in their org settings
    memoize def allow_org_setting?
      GitHub.codespaces_enabled? && org.codespaces_feature_enabled?
    end

    # Whether org admins can change the codespaces ownership setting in their org settings
    memoize def allow_org_admin_update_ownership_setting?
      !org.enterprise_managed_user_enabled?
    end

    memoize def plan_supports_codespaces?
      org.plan.present? && org.plan.supports?(:allow_codespaces)
    end

    # Their plan would otherwise support enabling codespaces, but we have
    # some restrictions in place, such as to prevent abuse.
    memoize def must_contact_support_to_enable?
      return false unless GitHub.codespaces_enabled?

      !allow_org_setting? && plan_supports_codespaces?
    end

    def self.must_contact_support_to_enable?(org:, user: nil)
      new(org: org, user: user).must_contact_support_to_enable?
    end

    # Their plan does not support enabling codespaces, but we want
    # to show an upsell banner.
    memoize def must_upgrade_to_use_codespaces?
      return false if GitHub.flipper[:codespaces_billing_free].enabled?(org)
      return false unless GitHub.codespaces_enabled?

      !allow_org_setting? && !plan_supports_codespaces?
    end

    memoize def org_admin_can_configure_private_networking?
      return false unless org.respond_to?(:business) && org.business.present?
      enterprise = org.business

      # Bypass Salus flag check for VNet only beta customers
      return true if enterprise.in_vnet_only_beta?

      enterprise.in_codespaces_salus_beta? && enterprise.feature_enabled?(:codespaces_vnet_injection_beta)
    end

    def self.owning_organization(repository)
      # Find out if there's an org that could be billed for this codespace
      # Repo must be org owned or a fork of an org owned repo
      if repository.organization && repository.owner == repository.organization
        repository.organization
      elsif repository.parent && repository.parent.organization && repository.parent.owner == repository.parent.organization
        repository.parent.organization
      else
        nil
      end
    end

    # Whether or not the codespaces feature has been enabled by the org for use of repos within the organization
    # Note: If you want to check if the codespaces feature is available for the organization
    # (whether they enabled it or not), use org.codespaces_feature_enabled?
    def self.enabled_by_organization?(org)
      org.codespaces_feature_enabled? && org.plan.codespaces_eligible? && !org.codespaces_access_disabled?
    end

    # === Permission Granting & Revoking ===
    #
    # Attempts to grant the role to the given user. Raises RoleGranterError if an error occurred.
    # This role grants the user access to create codespaces billable to the given organization.
    def self.grant_billing_permission!(user, org, role_granter: DEFAULT_ROLE_GRANTER)
      result = nil
      begin
        result = role_granter.new(actor: user, target: org, role: Role.codespace_org_creator_role).grant_unless_exists!
      rescue ActiveRecord::RecordInvalid, ::Permissions::Granters::RoleGranter::GrantFailure => e
        raise RoleGranterError.new(e)
      end

      unless !result.nil? && result.success?
        raise RoleGranterError.new("RoleGranter internally failed to grant the role.")
      end
    end

    # Revokes the role from the given actor if the role exists. Raises RoleGranterError if an error occurred.
    # Revoking access prevents the actor from creating codespaces billable to the given organization.
    # Actor could be user or team
    def self.revoke_billing_permission!(actor, org, role_granter: DEFAULT_ROLE_GRANTER)
      result = nil
      begin
        result = role_granter.new(actor: actor, target: org, role: Role.codespace_org_creator_role).revoke_if_exists!
      rescue ::Permissions::Granters::RoleGranter::GrantFailure => e
        raise RoleGranterError.new(e)
      end

      unless !result.nil? && result.success?
        raise RoleGranterError.new("RoleGranter internally failed to grant the role.")
      end
    end

    def self.billing_policy_members(org)
      visibility = org.organization_codespaces_user_limit

      if visibility == Configurable::OrganizationCodespacesUserLimit::SELECTED_USERS
        user_roles = UserRole.where(
          role: Role.codespace_org_creator_role,
          target_id: org.id,
          target_type: "Organization"
        )

        member_ids_with_role = user_roles.where(actor_type: "User").pluck(:actor_id).to_set

        [Api::Codespaces::Organization::SELECTED_MEMBERS, org.members.where(id: member_ids_with_role).pluck(:login)]
      elsif visibility == Configurable::OrganizationCodespacesUserLimit::ALL_USERS
        [Api::Codespaces::Organization::ALL_MEMBERS, []]
      elsif visibility == Configurable::OrganizationCodespacesUserLimit::ALL_USERS_AND_OUTSIDE_COLLABORATORS
        [Api::Codespaces::Organization::ALL_MEMBERS_AND_OUTSIDE_COLLABORATORS, []]
      else
        [visibility, []]
      end
    end

    class << self
      alias_method :allow_org_access!, :grant_billing_permission!
      alias_method :prevent_org_access!, :revoke_billing_permission!
      alias_method :allowed_org_members, :billing_policy_members
    end

    private

    def member?
      return @member if defined?(@member)
      @member = @known_org_relationship == :member || org.member?(user)
    end

    def outside_collaborator?
      return @enabled_collaborator_on_enabled_repo if defined?(@enabled_collaborator_on_enabled_repo)

      # We deliberately check only a single repo's collaborator status here. The way to check for multiple is to retrieve
      # the list of collaborator orgs and initialize this class with a known_org_relationship.
      @enabled_collaborator_on_enabled_repo = @known_org_relationship == :collaborator || (repo && org.user_is_outside_collaborator?(user, repo.id))
    end

    def member_or_collaborator?
      member? || outside_collaborator?
    end

    def limit_to_users?
      org.limit_organization_codespaces_to_users? && member?
    end

    def limit_to_users_and_collaborators?
      org.limit_organization_codespaces_to_users_and_collaborators? && member_or_collaborator?
    end
  end
end
