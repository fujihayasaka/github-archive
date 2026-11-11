# typed: true
# frozen_string_literal: true

# This module adds permissions checking and setting to the Project model. An
# actor can have three different levels of permissions on a Project:
#
# - :read
# - :write
# - :admin
#
# Higher levels inherently include lower levels (for example, having :write on
# a project means you also have :read). You can find more details on the
# semantics of these levels in our Abilities documentation:
#
# https://thehub.github.com/engineering/products-and-services/authorization/abilities/
#
# ### Checking permissions
#
# The interface for checking if an actor has a particular level of access on a
# project is via the `_by?` methods:
#
# project.readable_by?(actor)
# project.writable_by?(actor)
# project.adminable_by?(actor)
#
# ### Setting permissions
#
# #### Setting permissions on a project with Abilities enabled
#
# Currently, only Organization-owned Projects can have Abilities enabled.
#
# ##### Setting a project to public
#
# Projects are private by default, but you can update a project to make it
# public. When a project is public, everyone (even users without a GitHub
# account) will be able to read it.
#
# project.update_attribute(:public, true)
# project.readable_by?(nil) # => true
#
# ##### Setting an organization-wide permission
#
# You can grant a specified level of access to every member of the project's
# organization and revoke that organization-wide permission by calling:
#
# project.update_org_permission(:admin) # Grant the org :admin
# project.update_org_permission(:write) # Grant the org :write
# project.update_org_permission(:read)  # Grant the org :read
# project.update_org_permission(nil)    # Revoke the org's permission
#
# ##### Setting a team-wide permission
#
# You can add a project to a team with a particular permission, update that
# permission, and revoke that permission with the following methods:
#
# team.add_project(project, :write)
# team.update_project_permission(project, :read)
# team.remove_project(project)
#
# All three of these calls make use of the following method:
#
# project.update_team_permission(team, :admin) # Grant the team :admin
# project.update_team_permission(team, :write) # Grant the team :write
# project.update_team_permission(team, :read)  # Grant the team :read
# project.update_team_permission(team, nil)    # Revoke the team's permission
#
# ##### Setting per-user permissions
#
# You can set a permission for a particular user by calling:
#
# project.update_user_permission(user, :admin) # Grant the user :admin
# project.update_user_permission(user, :write) # Grant the user :write
# project.update_user_permission(user, :read)  # Grant the user :read
# project.update_user_permission(user, :nil)   # Revoke the user's permission
module Project::AbilityDependency
  extend T::Helpers
  requires_ancestor { Project }

  def owner_dependent_added
    owner.dependent_added(self) if owner_type == "Organization"
  end

  def owning_organization_id
    return unless owner_type == "Organization"
    owner_id
  end

  def owning_organization_type
    return unless owner_type == "Organization"
    owner_type
  end

  def public?
    if owner_type == "Repository"
      owner&.public?
    else
      super
    end
  end

  def readable_by?(user)
    if owner_type == "Repository"
      owner.projects_readable_by?(user)
    elsif owner_type == "Organization" && user&.can_have_granular_permissions?
      owner.resources.organization_projects.readable_by?(user)
    else
      super
    end
  end

  def async_readable_by?(user)
    async_owner.then do |owner|
      if owner.is_a?(Repository)
        owner.async_projects_readable_by?(user)
      elsif owner.is_a?(Organization) && user&.can_have_granular_permissions?
        owner.resources.organization_projects.async_readable_by?(user)
      else
        super
      end
    end
  end

  def writable_by?(user)
    if owner_type == "Repository"
      owner.projects_writable_by?(user)
    elsif owner_type == "Organization" && user&.can_have_granular_permissions?
      owner.resources.organization_projects.writable_by?(user)
    else
      super
    end
  end

  def async_writable_by?(user)
    async_owner.then do |owner|
      if owner.is_a?(Repository)
        owner.async_projects_writable_by?(user)
      elsif owner.is_a?(Organization) && user&.can_have_granular_permissions?
        owner.resources.organization_projects.async_writable_by?(user)
      else
        super
      end
    end
  end

  def viewer_can_update?(viewer)
    async_viewer_can_update?(viewer).sync
  end

  def async_viewer_can_update?(viewer)
    return Promise.resolve(false) if viewer.nil?

    async_owner.then do |owner|
      if owner.is_a?(Repository) && owner.locked_on_migration?
        false
      else
        async_writable_by?(viewer)
      end
    end
  end

  # If a user can update a project, they can also reopen it.
  alias :async_closable_by? :async_viewer_can_update?
  alias :async_reopenable_by? :async_viewer_can_update?

  def adminable_by?(user)
    if owner_type == "Repository"
      owner.projects_adminable_by?(user)
    elsif owner_type == "Organization" && user&.can_have_granular_permissions?
      owner.resources.organization_projects.adminable_by?(user)
    else
      super
    end
  end

  def async_adminable_by?(user)
    async_owner.then do |owner|
      if owner.is_a?(Repository)
        owner.async_projects_adminable_by?(user)
      elsif owner.is_a?(Organization) && user&.can_have_granular_permissions?
        owner.resources.organization_projects.async_adminable_by?(user)
      else
        super
      end
    end
  end

  def viewer_can_change_visibility?(viewer)
    # Visibility cannot be changed for a project that is tied to a repository (instead, visibility
    # is governed by the repository itself).
    return false if owner.is_a?(Repository)

    # Viewer must be a project admin to change visibility.
    return false unless adminable_by?(viewer)

    # For projects that are not org-owned, the above checks are sufficient.
    return true unless owner.is_a?(Organization)

    # If the user is a project admin (as verified above) and ordinary org members are allowed
    # to change project visibility, then allow the change.
    return true if owner.members_can_change_project_visibility?

    # Lastly, allow the change if the user is an org admin.
    owner.adminable_by?(viewer)
  end

  def async_viewer_can_administer?(viewer)
    return Promise.resolve(false) if viewer.nil?

    async_owner.then do |owner|
      if owner.is_a?(Repository) && owner.locked_on_migration?
        false
      else
        async_adminable_by?(viewer)
      end
    end
  end

  # Public: Project's access control consults more than just abilities.
  #
  # actor  - a User or Team, though it's generally a User.
  # action - a :read, :write, or :admin Symbol
  def permit?(actor, action)
    actor = actor.ability_delegate

    return false if new_record?
    return false if destroyed?
    return false if marked_for_deletion?
    return false if actor.is_a?(User) && actor.organization?

    # everything can read public projects
    return true if public? && action == :read

    # an actor is required if the project isn't public
    return false if actor.nil?

    # an actor is operating on something it owns
    return true if actor.class == User && actor.id == owner_id && actor.class.to_s == owner_type

    # the actor's abilities allow it (this hits the DB)
    super
  end

  # Public: Project's access control consults more than just abilities.
  #
  # actor  - a User or Team, though it's generally a User.
  # action - a :read, :write, or :admin Symbol
  #
  # Returns Promise<bool>
  def async_permit?(actor, action)
    actor = actor.ability_delegate

    return Promise.resolve(false) if new_record?
    return Promise.resolve(false) if destroyed?
    return Promise.resolve(false) if marked_for_deletion?
    return Promise.resolve(false) if actor.is_a?(User) && actor.organization?

    # everything can read public projects
    return Promise.resolve(true) if public? && action == :read

    # an actor is required if the project isn't public
    return Promise.resolve(false) if actor.nil?

    # an actor is operating on something it owns
    return Promise.resolve(true) if actor.class == User && actor.id == owner_id && actor.class.to_s == owner_type

    # the actor's abilities allow it (this hits the DB)
    super
  end

  def org_permission
    if owner.is_a?(Organization)
      Authorization.service.direct_ability_between(actor: owner, subject: self)&.action&.to_sym
    else
      nil
    end
  end

  # Public: Update the owning org's permission on the project.
  #
  # action - :read, :write, :admin, or nil, the latter of which will revoke the
  #          org's permission.
  #
  # Returns nothing.
  def update_org_permission(action)
    raise "This should only be called on org-owned projects" unless owner.is_a?(Organization)

    previous_action = direct_ability_with_actor(owner)&.action

    update_actor_permission(owner, action)
    instrument :update_org_permission, org: owner, changes: { permission: action, old_permission: previous_action }
  end

  # Public: Update specified team's permission on the project.
  #
  # team - Team to change the permission level of.
  # action - :read, :write, :admin, or nil, the latter of which will revoke the
  #          team's permission.
  #
  # Returns nothing.
  def update_team_permission(team, action)
    raise ArgumentError, "A Team must be passed, but a #{team.class} was passed instead" unless team.instance_of?(Team)
    raise "This should only be called on org-owned projects" unless owner.is_a?(Organization)

    previous_action = direct_ability_with_actor(team)&.action

    update_actor_permission(team, action)
    instrument :update_team_permission, team: team, changes: { permission: action, old_permission: previous_action }
  end

  # Public: Update specified user's permission on the project.
  #
  # user - User to change the permission level of.
  # action - :read, :write, :admin, or nil, the latter of which will revoke the
  #          user's permission.
  #
  # Returns nothing.
  def update_user_permission(user, action)
    raise ArgumentError, "A User must be passed, but a #{user.class} was passed instead" unless user.instance_of?(User)

    # If we are trying to clear the user's permission but the user cannot read the project, return early.
    return if action.blank? && !readable_by?(user)

    previous_action = direct_ability_with_actor(user)&.action

    update_actor_permission(user, action)
    instrument :update_user_permission, user: user, changes: { permission: action, old_permission: previous_action }
  end

  def direct_teams
    return Team.none unless owner_type == "Organization"

    direct_team_abilities = Authorization.service.direct_abilities_on_subject(subject: self, actor_type: Team)
    Team.where(id: direct_team_abilities.map(&:actor_id), organization_id: owner_id)
  end

  def direct_collaborators(permission: :any)
    direct_user_abilities = Authorization.service.direct_abilities_on_subject(
      subject: self,
      actor_type: User,
      action: permission,
    )
    User.where(id: direct_user_abilities.map(&:actor_id))
  end

  def outside_collaborators(permission: :any)
    direct_user_abilities = Authorization.service.direct_abilities_on_subject(
      subject: self,
      actor_type: User,
      action: permission,
    )

    User.where(
      "id IN (?) AND id NOT IN (?)",
      direct_user_abilities.map(&:actor_id),
      owner.member_ids,
    )
  end

  def users_with_access(permission: :any)
    ids = Authorization.service.actor_ids(
      subject: ability_delegate,
      actor_type: User,
      through: [Team, Organization],
      action: permission,
    )

    ids |= if owner_type == "User"
      [owner_id]
    else
      owner.admin_ids
    end

    User.where(id: ids)
  end

  # All the teams that have access to this project and that the specified user
  # can see.
  #
  # user - The user whose team visibility we want to filter by.
  #
  # Returns a Team scope.
  def visible_teams_for(user)
    return Team.none if owner_type != "Organization"

    owner.visible_teams_for(user).where(id: Ability.teams_direct_on_projects(
      project_id: id,
    ).pluck(:actor_id))
  end

  def addable_teams_for(actor, query: nil)
    return Team.none unless owner.is_a?(Organization)
    return Team.none unless owner.member?(actor)
    return Team.none unless adminable_by?(actor)

    scope = owner.visible_teams_for(actor)

    query = ActiveRecord::Base.sanitize_sql_like(query.to_s.strip.downcase)
    if query.present?
      scope = scope.where(["name LIKE ? OR slug LIKE ?", "%#{query}%", "%#{query}%"])
    end

    scope
  end

  private

  def direct_ability_with_actor(actor)
    Authorization.service.direct_ability_between(actor: actor, subject: self)
  end

  # Public: Update specified actor's permission on the project.
  #
  # actor - Actor (such as a User or Team) to change the permission level of.
  # action - :read, :write, :admin, or nil, the latter of which will revoke the
  #          actor's permission.
  #
  # Returns nothing.
  def update_actor_permission(actor, action)
    if action.present?
      grant(actor, action)
    else
      revoke(actor)
    end

    nil
  end
end
