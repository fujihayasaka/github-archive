# typed: true
# frozen_string_literal: true

# Adds organizations-specific functionality to users. That is, real world
# users who can log in to the site and do fun things.
#
# It includes the various organizations-related associations, team
# membership discovery, organization discovery, etc.
module User::OrganizationsDependency
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { User }

  included do
    T.bind(self, T.class_of(User))
    before_destroy :verify_no_owned_organizations
    before_destroy :remove_from_teams
  end

  # Public: An ActiveRecord scope representing the teams this user belongs to.
  def teams(with_ancestors: false)
    async_teams(with_ancestors: with_ancestors).sync
  end

  def team_ids(with_ancestors: false)
    async_team_ids(with_ancestors: with_ancestors).sync
  end

  # Public: Get this user's teams that are visible to the provided viewer.
  # Doesn't include teams this user is a member of indirectly via child teams.
  # Returns an ActiveRecord relation
  def async_visible_teams_for(viewer)
    async_teams.then do |user_teams|
      next Team.none unless viewer
      if viewer == self
        # If viewing your own teams, just make sure the org still exists
        if viewer.feature_enabled?(:async_visible_teams_for_soft_deleted_org_fix)
          next user_teams.joins(:organization).merge(Organization.active)
        else
          next user_teams.joins(:organization)
        end
      end

      shared_org_ids = organization_ids & viewer.organization_ids

      visible_team_ids = Organization.where(id: shared_org_ids).flat_map do |org|
        org.visible_teams_for(viewer).pluck(:id)
      end

      user_teams.where(id: visible_team_ids)
    end
  end

  # Public: Returns a Promise that resolves as a Team relation for this User's
  # teams.
  #
  # If `with_ancestors:` is `true`, loads Teams and their ancestors
  # (the Teams this user is a member of directly and indirectly).
  # Defaults to `false`.
  #
  # Returns an ActiveRecord::Relation.
  def async_teams(with_ancestors: false)
    async_team_ids(with_ancestors: with_ancestors).then do |team_ids|
      next Team.none unless team_ids.any?
      Team.where(id: team_ids)
    end
  end

  def async_team_ids(with_ancestors: false)
    Platform::Loaders::UserTeams.load(self, with_ancestors: with_ancestors)
  end

  # Public: Get the teams that a user is a member of.
  #
  # viewer - a user that is viewing the teams for another user
  #
  # optional arguments
  #
  # query:              - The user-provided query string with any filters (example: `role`) removed
  # order_by_field      - a String specifying the sort field
  # order_by_direction  - a String specifying the sort direction
  #
  # Returns an ActiveRecord::Relation
  sig do
    params(
      viewer: ::User,
      query: T.nilable(String),
      order_by_field: String,
      order_by_direction: String,
    ).returns(ActiveRecord::Relation)
  end
  def filter_teams(viewer, query: nil, order_by_field: "name", order_by_direction: "ASC")
    query = ActiveRecord::Base.sanitize_sql_like(query.to_s.strip.downcase)

    ActiveRecord::Base.connected_to(role: :reading) do
      visible_team_ids = if GitHub.enterprise? && viewer.site_admin? ||
        viewer.is_enterprise_managed? && viewer.enterprise_managed_business&.owner?(viewer)

        Organization.where(id: organization_ids).flat_map do |org|
          next unless org.active?
          org.team_ids
        end
      else
        organization_ids_visible_viewer = organization_ids_visible_to(viewer)
        shared_org_ids = organization_ids & organization_ids_visible_viewer

        Organization.where(id: shared_org_ids).flat_map do |org|
          next unless org.active?
          org.visible_teams_for(viewer).pluck(:id)
        end
      end

      scope = teams.where(id: visible_team_ids.uniq)

      if query.present?
        scope = scope.where(["teams.name LIKE :query", { query: "%#{query}%" }])
      end

      scope = scope.order("teams.#{order_by_field} #{order_by_direction}")
    end
  end

  # Public: The organizations this user is associated with.
  def organizations
    organization_filter.scope
  end

  # Public: The organization ids this user is associated with. Avoids an extra
  # look up of organizations as opposed to User#organizations.
  def organization_ids
    organization_filter.scoped_ids
  end

  def async_organization_ids
    Platform::Loaders::UserOrganizations.load(self)
  end

  private def organization_filter
    @user_organization_filter ||= User::OrganizationFilter.new(self)
  end

  # Public: Get the organizations that a user is a member of.
  #
  # viewer - a user that is viewing the organizations for another user
  #
  # optional arguments
  #
  # query:              - The user-provided query string with any filters (example: `role`) removed
  # order_by_field      - a String specifying the sort field
  # order_by_direction  - a String specifying the sort direction
  # org_member_type     - filter to return organizations based on the user's membership type (:admin, :member_without_admin, :all)
  #                       default: :all
  #
  # Returns an ActiveRecord::Relation
  sig do
    params(
      viewer: ::User,
      query: T.nilable(String),
      order_by_field: String,
      order_by_direction: String,
      org_member_type: Symbol,
    ).returns(ActiveRecord::Relation)
  end
  def filter_organizations(viewer, query: nil, order_by_field: "login", order_by_direction: "ASC", org_member_type: :all)
    query = ActiveRecord::Base.sanitize_sql_like(query.to_s.strip.downcase)

    ActiveRecord::Base.connected_to(role: :reading) do
      scope = if GitHub.enterprise? && viewer.site_admin? ||
        viewer.is_enterprise_managed? && viewer.enterprise_managed_business&.owner?(viewer)
        organizations
      else
        organizations_visible_to(viewer)
      end

      if query.present?
        scope = scope.includes(:profile)
          .where(["users.login LIKE :query OR profiles.name LIKE :query", { query: "%#{query}%" }])
          .references(:profile)
      end

      unless org_member_type == :all
        viewable_org_ids = case org_member_type
        when :admin
          owned_organization_ids
        else
          organization_ids - owned_organization_ids
        end

        scope = scope.where(id: viewable_org_ids)
      end

      scope = scope.order("users.#{order_by_field} #{order_by_direction}")
    end
  end

  # Public: The IDs of organizations that this user is a member of where the membership is
  # visible to the given viewer.
  def organization_ids_visible_to(viewer)
    return organization_ids if viewer == self

    # Viewers can see public organizations and organizations where they are also a member
    viewer_organization_ids = viewer&.organization_ids || []
    public_organization_ids = private_profile_for?(viewer) ? [] : public_organizations.pluck(:id)
    org_ids_visible_to_viewer = public_organization_ids | viewer_organization_ids

    organization_ids & org_ids_visible_to_viewer
  end

  # Public: The organizations that this user is a member of where the membership is
  # visible to the given viewer.
  def organizations_visible_to(viewer)
    return organizations if viewer == self
    organizations.where(id: organization_ids_visible_to(viewer))
  end

  def organizations_info
    organizations_hash = Ability.where(
      actor_id: ability_id,
      actor_type: ability_type,
      subject_type: "Organization",
      priority: Ability.priorities[:direct],
    ).index_by(&:subject_id)

    organizations = Organization.active.includes(:business, :profile, :trade_controls_restriction).where(id: organizations_hash.keys)

    # We need to preload to avoid a N+1 checking members_can_create_repositories? down below
    non_admin_orgs = organizations.filter { |org| organizations_hash[org.id].action.to_sym == :read }

    Configurable.preload_configuration(non_admin_orgs)

    @legacy_admin_teams_by_org = if non_admin_orgs.any?
      teams.legacy_admin.where(organization_id: non_admin_orgs.map(&:id)).group_by(&:organization_id)
    else
      {}
    end

    results = organizations.each_with_object({}) do |org, hash|
      access = organizations_hash[org.id].action.to_sym
      hash[org] = organization_hash(org, access)
    end

    @legacy_admin_teams_by_org = nil

    results
  end

  # Public: Gets a hash with attributes of the provided organization relative to this user.
  sig { params(org: Organization, access: Symbol).returns(T::Hash[Symbol, T.untyped]) }
  def organization_hash(org, access)
    if access == :read
      if org.members_can_create_repositories?
        access = :write
      else
        has_legacy_admin_teams = if @legacy_admin_teams_by_org.nil?
          teams.owned_by(org).legacy_admin.any?
        else
          @legacy_admin_teams_by_org[T.must(org.id)]&.any?
        end

        if has_legacy_admin_teams
          # Keep support for allowing members of legacy admin teams to add repos.
          access = :admin
        end
      end
    end

    org_hash = { access: access }

    case access
    when :write
      org_hash[:allow_public_repos] = org.members_can_create_public_repositories?
      org_hash[:allow_private_repos] = org.members_can_create_private_repositories?
      org_hash[:allow_internal_repos] = org.members_can_create_internal_repositories?
    when :read
      org_hash[:allow_public_repos] = org_hash[:allow_private_repos] = org_hash[:allow_internal_repos] = false
    else
      org_hash[:allow_public_repos] = org_hash[:allow_private_repos] = true
      org_hash[:allow_internal_repos] = org.supports_internal_repositories?
    end

    if org.archived?
      org_hash[:custom_disabled_message] = "(Archived)"
    end

    org_hash
  end

  def organizations_info_sorted_hash
    organizations_info.sort_by { |o| o[0].login.downcase }.to_h
  end

  def installable_apps
    Marketplace::Listing.quick_installable_for(T.cast(self, User))
  end

  def installable_marketplace_apps_hash
    installable = { self => installable_apps }

    if GitHub.create_repo_perf?
      orgs = organizations_info_sorted_hash
      org_ids = orgs.keys.map(&:id)
      org_installable = Marketplace::Public.quick_installable_for_orgs(organization_ids: org_ids)

      orgs.each_with_object(installable) do |(org, info), apps|
        apps[org] = org_installable[org.id] unless info[:access] == :read
      end
    else
      organizations_info_sorted_hash.each_with_object(installable) do |(org, info), apps|
        apps[org] = Marketplace::Listing.quick_installable_for(org) unless info[:access] == :read
      end
    end
  end

  # Public: The active organizations this user is invited to.
  def invited_organizations
    OrganizationInvitation.where(invitee_id: id, accepted_at: nil).includes(:organization).select { |i| i.organization.active? }.map(&:organization)
  end

  # The ids of all organizations this user is an owner of.
  #
  # Returns an Array of Organization ids
  def owned_organization_ids
    @owned_organization_ids ||= Ability.user_admin_on_organizations(
      actor_id: id,
    ).pluck(:subject_id)
  end

  # The organizations this user is an owner of.
  #
  # Returns an Array of Organization objects (or an empty Array)
  def owned_organizations
    # Returning a scope rather than an array so users of this method that
    # call `count`, etc. don't need to load full objects for every owned org.
    Organization.active.where(id: owned_organization_ids)
  end

  # Public: Get the orgs where the user is the only owner.
  #
  # Returns ActiveRecord::Relation.
  def solitarily_owned_organizations
    owned_org_ids_with_other_owners = Ability.admin.where({
      actor_type: "User",
      subject_type: "Organization",
      subject_id: owned_organization_ids,
      priority: Ability.priorities[:direct],
    }).where.not(
      actor_id: id,
    ).pluck(:subject_id).compact.uniq

    Organization.active.where(
      id: owned_organization_ids - owned_org_ids_with_other_owners
    )
  end

  # Finds organizations that this user is a publicized member of.
  #
  # Returns an Array of Organization instances.
  def public_organizations
    Organization.active.where(
      "public_org_members.user_id = ?", id
    ).joins(
      "inner join public_org_members on users.id = public_org_members.organization_id",
    )
  end

  # Public: The organizations that the user is associated with via direct
  # membership or outside collaboratorship.
  #
  # Added for authorizing OAuth apps and CAP filter evaluation. Includes organizations that this user is
  # able to request authorization for.
  #
  # Returns an ActiveRecord::Relation of Organizations.
  def authorizable_organizations
    @authorizable_organizations ||= Organization.active.where(id: authorizable_organization_ids).order(:login)
  end

  def authorizable_organization_ids
    @authorizable_organization_ids if @authorizable_organization_ids

    repository_ids = associated_repository_ids(including: [:direct])

    # We can find repositories owned by organizations (and not just forks of
    # private org repos) by seeing that both its organization_id is set, and it
    # matches the owner_id
    organization_ids = Repository.where("organization_id = owner_id AND id IN (?)", repository_ids).distinct.pluck(:organization_id)
    organization_ids |= organization_filter.unscoped_ids

    @authorizable_organization_ids = organization_ids.uniq
    @authorizable_organization_ids
  end

  # Can this user add members for the specified org and teams?
  #
  # org   - The organization the user wants to add members for.
  # teams - (Optional) The teams the user wants to add members for.
  # role  - (Optional) The role the user wants to add member for
  #
  # Returns a boolean.
  def can_add_members_for?(org, teams: [], role: nil)
    can_send_invitations_for?(org, teams: teams, role: role)
  end

  # Can this user send invitations for the specified org and teams?
  #
  # org   - The organization the user wants to send invitations for.
  # teams - (Optional) The teams the user wants to send invitations for.
  # role  - (Optional) The role the user wants to send invitations for
  #
  # Returns a boolean.
  def can_send_invitations_for?(org, teams: [], role: nil)
    return false if teams.any? { |t| t.organization_id != org.id }

    # The inviter can be the organization in certain obscure cases, like for an
    # invitation sent when transforming a user into an org.
    return true if org == self

    # In direct and legacy org membership, org admins/owners can send
    # invitations.
    return true if org.adminable_by?(self)

    # allow enterprise account owners to invite users to organizations.
    # currently only done via SCIM
    return true if org.business && (GitHub.single_business_environment? || (org.business.saml_sso_enabled? && GitHub.flipper[:enterprise_idp_provisioning].enabled?(org.business))) && org.business.owner?(self)

    # A GitHub App Bot, whose current installation
    # has write permission on the org's members
    if self.is_a?(Bot) && self.respond_to?(:installation)
      return true if org.resources.members.writable_by?(self.installation)
      return true if org.business && org.business.resources.enterprise_administration.writable_by?(self.installation)
    end

    # Is this user a manager inviting another manager to the organization?
    manager_adding_another?(org, role)
  end

  # Returns true if this user is a manager adding another manager to this org.
  #
  # org  - the organization to which the user wants to add another user
  # role - the role the new user will be given in the organization
  #
  # Only returns true if the manager is adding another manager of the same kind.
  #
  # Returns a boolean.
  def manager_adding_another?(org, role)
    # Billing managers can invite other billing managers
    role == :billing_manager && org.billing_manager?(self)
  end

  # called when destroying the user
  def remove_from_teams
    teams.each { |team| team.remove_member self }
  end

  # Verify that the user doesn't own any organizations before it is deleted.
  #
  # Returns a Boolean
  def verify_no_owned_organizations
    error_message = if !GitHub.enterprise? && owned_organizations.any?
      "You must transfer or delete all owned organizations"
    elsif solitarily_owned_organizations.any?
      "You must transfer or delete all organizations where you're the only owner"
    end

    if error_message.present?
      errors.add(:organizations, error_message)

      throw :abort
    else
      true
    end
  end

  # Public: Get the organization this user was most recently added to.
  #
  # Returns an Organization or nil.
  sig { returns(T.nilable(Organization)) }
  def newest_organization
    newest_org_id = Ability.organization_memberships_for_user(actor_id: id).newest_first
      .limit(50)
      .pluck(:subject_id)
    Organization.active.where(id: newest_org_id).first
  end

  # Internal: Find all Organizations for which this user is a billing manager
  #
  # Returns an ActiveRecord::Relation object
  def billing_manager_organizations
    Organization.active.where(id: billing_manager_organization_ids)
  end

  # Public: Find the IDs of all organizations that this user is an admin (owner) or billing
  # manager of.
  #
  # Returns an Array[Integer].
  def owned_or_billing_manager_organization_ids
    @owned_or_billing_manager_organization_ids ||= Ability
      .user_billing_manager_on_organizations(actor_id: ability_id, actor_type: ability_type)
      .or(Ability.user_admin_on_organizations(actor_id: id))
      .pluck(:subject_id)
  end

  # Public: Find all Organizations for which this user is a billing manager or owner (admin).
  #
  # Be careful with how you use this, as billing managers should
  # not have access to an organization's repositories or
  # member list.
  #
  # Returns an ActiveRecord::Relation object
  def owned_or_billing_manager_organizations
    Organization.active.where(id: owned_or_billing_manager_organization_ids)
  end

  # Public: Get IDs of organizations this user either belongs to as a regular member or acts as billing manager of.
  #
  # Returns a Hash[Symbol] => Set of Integers. The keys are :member and :billing_manager, and the values are the
  # organization IDs where this user has that role.
  def organization_ids_by_member_or_billing_manager_status
    if @organization_ids_by_member_or_billing_manager_status
      return @organization_ids_by_member_or_billing_manager_status
    end

    abilities = user_abilities_for_organizations
    result = { billing_manager: Set.new, member: Set.new }
    abilities.each do |ability|
      key = ability.subject_type == "Organization::BillingManagement" ? :billing_manager : :member
      result[key].add(ability.subject_id)
    end
    @organization_ids_by_member_or_billing_manager_status = result
  end

  def member_or_billing_manager_for_any_organization?
    user_abilities_for_organizations.exists?
  end

  def user_abilities_for_organizations
    billing_manager_subject = "Organization::BillingManagement"
    Ability.where(
      actor_type: "User",
      actor_id: id,
      subject_type: ["Organization", billing_manager_subject],
    ).where("(priority=1 OR subject_type=?)", billing_manager_subject).select(:subject_id, :subject_type)
  end

  # Internal: Find the IDs of all organizations that this user either belongs to or is a billing
  # manager for.
  #
  # Returns an Array[Integer].
  def member_or_billing_manager_organization_ids
    @member_or_billing_manager_organization_ids ||= (organization_ids_by_member_or_billing_manager_status[:member] +
      organization_ids_by_member_or_billing_manager_status[:billing_manager]).to_a
  end

  # Public: The organizations this user is a member of or has billing management access to.
  #
  # Be careful with how you use this, as billing managers should
  # not have access to an organization's repositories or
  # member list.
  #
  # Returns an ActiveRecord::Relation of Organization.
  def member_or_billing_manager_organizations
    Organization.active.where(id: member_or_billing_manager_organization_ids)
  end

  # Internal: Find the IDs of all organizations that this user is a billing
  #           manager for.
  #
  # Returns an Array[Integer].
  def billing_manager_organization_ids
    @billing_manager_organization_ids ||= organization_ids_by_member_or_billing_manager_status[:billing_manager].to_a
  end

  # Public: The user's roles on the given Organization ORG
  #
  # Returns an Array of Strings
  def abilities_on_organization(org)
    [].tap do |memo|
      memo << "Owner" if org.adminable_by?(self)
      memo << "Member" if !org.adminable_by?(self) && org.direct_member?(self)
      memo << "Billing manager" if org.billing_manager?(self)

      if org.collaborators.exists?(self)
        count = collaborations_count(org)
        repositories = (count == 1) ? "repository" : "repositories"
        memo << "Collaborator on #{count} #{repositories}"
      end
    end
  end

  # Public: The number of outside collaborations the user has with a given
  #         Organization ORG
  #
  # Returns an Array of Strings
  def collaborations_count(org)
    repos = org.collaborating_repositories_for(id)
    repos.fetch(id).count
  end

  # Returns a Promise that resolves to a relation of organizations
  # that are mentioned in the company profile field
  # and are also verified as organizations for the user
  def async_verified_company_organizations
    async_profile.then do |profile|
      if profile&.company.present?
        mentioned_logins = []
        GitHub::HTML::MentionFilter.mentioned_logins_in(profile.company) do |_, login, _|
          mentioned_logins << login
        end
        public_organizations.where(login: mentioned_logins)
      else
        Organization.none
      end
    end
  end

  def dashboard_contexts
    @dashboard_contexts ||= User::DashboardContexts.new(user: self)
  end

  # Public: The resources for a user to be used by default with a
  # Conditional Access Policy filter.
  #
  # If this is an EMU, other EMUs in the Business need to be considered as
  # resources for input to CAP filtering, in addition to the Organizations
  # with which the User is associated.
  #
  # Otherwise, only the Organizations with which the User is associated are
  # considered.
  #
  # Example usage:
  #
  # cap_filter.unauthorized_resource_ids(current_user.resources_for_cap_filter)
  #
  # direct_and_indirect_orgs - Boolean indicating whether to use both direct
  #   and indirect Organizations with CAP filter.
  #
  # Returns Array of User/Organization
  def resources_for_cap_filter(direct_and_indirect_orgs: false)
    orgs = if direct_and_indirect_orgs
      self.direct_and_indirect_orgs
    else
      if self.feature_enabled?(:cap_filter_consider_outside_collabs)
        self.authorizable_organizations
      else
        self.organizations
      end
    end

    if self.is_enterprise_managed?
      emus = []

      if self.enterprise_managed_business&.ip_allowlist_user_level_enforcement_enabled? ||
        self.enterprise_managed_business&.idp_cap_for_web_enabled?
        emus = self.enterprise_managed_business
          .user_accounts
          .includes(:user)
          .map { |account| account&.user }.compact
      end

      emus + orgs
    else
      orgs
    end
  end
end
