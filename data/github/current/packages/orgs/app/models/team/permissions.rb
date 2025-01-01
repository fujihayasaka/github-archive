# typed: true
# frozen_string_literal: true

# Public: Check a user's ability to add, remove, change, or see a team.
module Team::Permissions
  extend T::Helpers
  requires_ancestor { Team }

  # Public: Can a user become a member of this team? Teams mapped to an
  # external LDAP service can't be joined. Administrators can join any team.
  def joinable_by?(user)
    return false if ldap_mapped? || member?(user)
    adminable_by?(user)
  end

  # Public: Can a user's membership be removed? Users can't leave a team mapped
  # to an external LDAP service.
  def leavable_by?(user)
    return false if ldap_mapped?

    member?(user)
  end

  # Public: Can the given user see this team?
  #
  # Returns a Boolean.
  def visible_to?(user)
    async_visible_to?(user).sync
  end

  # Given that the viewer IS NOT a team member or of instance User, can they see this team?
  private def visible_to_non_team_member(viewer)
    async_organization.then do |org|

      async_programmatic_actor_permissons = Promise.all([
        Promise.resolve(false),
        Promise.resolve(false),
      ])
      if viewer.can_have_granular_permissions?
        async_programmatic_actor_permissons = Promise.all([
          org.resources.members.async_readable_by?(viewer),
          org.resources.team_discussions.async_readable_by?(viewer),
        ])
      end

      async_programmatic_actor_permissons.then do |can_read_members, can_read_team_discussions|
        next true if can_read_members || can_read_team_discussions

        # Is the viewer is an org member viewing a non-secret team, or is the viewer an org admin?
        next false unless viewer.is_a?(User)

        # actor is a User and subject is an Organization
        ability = ::Ability.where(
          actor_id: viewer.id,
          actor_type: "User",
          subject_id: org.id,
          subject_type: "Organization",
        ).first

        ability.present? && (ability.admin? || !secret?)
      end
    end
  end

  # Public: Can the given viewer see this team?
  #
  # This method resolves to true in the following situations:
  #   1. viewer is an IntegrationInstallation with read permissions on the
  #      organization's members or team discussions
  #   2. viewer is a Bot whose IntegrationInstallation has read permissions on
  #      the organization's members or team discussions
  #   3. viewer is a ProgrammaticAccessBot whose OrganizationProgrammaticAccessGrant
  #      has read permissions on the organization's members or team discussions
  #   4. viewer is a User and an org member and the team is not secret
  #   5. viewer is a User and a member of this team
  #   6. viewer is a User and an admin of the organization
  #
  # viewer - One of {IntegrationInstallation, Bot, ProgrammaticAccessBot, (non-bot) User}.
  #
  # Returns a Promise of a Boolean.
  def async_visible_to?(viewer)
    return Promise.resolve(false) unless viewer

    return Promise.resolve(visible_to_non_team_member(viewer)) unless viewer.is_a?(User)

    Platform::Loaders::IsTeamMemberCheck.load(viewer.id, id).then do |is_team_member|
      next true if is_team_member
      visible_to_non_team_member(viewer)
    end
  end

  def can_create_team_discussion?(actor)
    async_can_create_team_discussion?(actor).sync
  end

  # Can the given actor create a team discussion?
  #
  # actor - One of {IntegrationInstallation, Bot, ProgrammaticAccessBot, (non-bot) User}.
  #
  # Returns a Promise of a Boolean.
  def async_can_create_team_discussion?(actor)
    return Promise.resolve(false) unless actor

    async_organization.then do |org|
      org.async_team_discussions_allowed?.then do |discussions_allowed|
        next false unless discussions_allowed

        async_programmatic_actor_can_create = \
          if actor.can_have_granular_permissions?
            org.resources.team_discussions.async_writable_by?(actor)
          else
            Promise.resolve(true)
          end

        Promise
          .all([async_visible_to?(actor), async_programmatic_actor_can_create])
          .then(&:all?)
      end
    end
  end

  # Public: Can a user associate a repository with this team?
  def can_add_repositories?(user, allow_owners_team: false)
    return false if legacy_owners? && !allow_owners_team
    return true if adminable_by?(user)

    # Keep support for allowing members of legacy admin teams to add repos.
    admin? && member?(user)
  end

  # Public: get the permission this team has on the given repository.
  def permission_for(repo)
    return unless repo
    action = Authorization.service.most_capable_action_between(actor: self, subject: repo)
    Team::ABILITIES_TO_PERMISSIONS[action]
  end

  # Internal: Overrides Ability::Subject#grant?, only allowing users.
  def grant?(actor, action)
    super && actor.is_a?(User) && actor.user?
  end

  # Internal: Overrides Ability::Subject#permit?, also allowing read access
  # to non-secret teams by actors who can read this team's organization.
  def permit?(actor, action)
    async_permit?(actor, action).sync
  end

  def async_permit?(actor, action)
    super.then do |result|
      if result
        if action == :read
          true
        else
          async_enterprise_team_managed?.then do |enterprise_team_managed|
            !enterprise_team_managed
          end
        end
      elsif !secret? && action == :read
        actor = actor.ability_delegate
        # TODO: Does this need to be async?
        T.unsafe(organization).direct_member?(actor)
      else
        false
      end
    end
  end

  def can_have_granular_permissions?
    false
  end

  # Public: Does the given user have the ability to create a new team post?
  #
  # Returns: Boolean
  def team_post_creatable_by?(user)
    async_fgp_team_post_creatable?(user).sync
  end

  # Public: Does the given user have the ability to create a new team post?
  #
  # Authz looks at whether the team allows discussions, whether posting is restricted
  # to specific users, and whether user has the correct role to post
  #
  # Returns: Promise that resolves to a Boolean
  def async_fgp_team_post_creatable?(user)
    async_fgp_team_post_creatable_result(user).then do |decision|
      decision.allow?
    end
  end

  # Internal: Setup correct authorizer parameters for determining if user has the
  # ability to create a new team post
  #
  # Returns: an autzd authorizer result
  def async_fgp_team_post_creatable_result(user)
    Platform::Loaders::Permissions::BatchAuthorize.load(
      action: :write_team_post,
      actor: user,
      subject: self,
      context: {
        "actor.is_team_maintainer" => maintainer?(user)
      }.symbolize_keys
    )
  end
end
