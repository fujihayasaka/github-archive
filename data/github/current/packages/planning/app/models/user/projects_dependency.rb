# typed: false
# frozen_string_literal: true

module User::ProjectsDependency
  def projects_enabled?
    true
  end

  def async_projects_enabled?
    Promise.resolve(true)
  end

  def visible_projects_for(user)
    GitHub.dogstats.distribution_time("project_permissions.dist.visible_projects_for", tags: ["owner_type:user"]) do
      # Logged-out users can only see public projects.
      return projects.where(public: true) if user.nil?

      # Blocked users cannot see any projects
      return Project.none if user.blocked_by?(owner)

      # Bots can't see user projects.
      return Project.none if user.can_have_granular_permissions?

      # The user can see all of their projects projects
      return projects.scoped if self == user

      # All other users need to go through abilities
      ids = Ability.where(
        subject_type: "Project",
        actor_id: user.id,
        actor_type: "User",
        priority: Ability.priorities[:direct],
      ).pluck(:subject_id)

      projects.where(public: true).or(projects.where(id: ids))
    end
  end

  def writable_projects_for(user)
    GitHub.dogstats.distribution_time("project_permissions.dist.writable_projects_for", tags: ["owner_type:user"]) do
      # Logged out users can't write to any projects.
      return Project.none if user.nil?

      # Blocked users cannot see any projects
      return Project.none if user.blocked_by?(owner)

      # Bots can't write to user projects.
      return Project.none if user.can_have_granular_permissions?

      # Users can write to their own projects
      return projects.scoped if user == self

      # All other users need to go through abilities
      ids = Ability.where(
        subject_type: "Project",
        actor_id: user.id,
        actor_type: "User",
        priority: Ability.priorities[:direct],
        action: [Ability.actions[:write], Ability.actions[:admin]],
      ).pluck(:subject_id)

      projects.where(id: ids)
    end
  end
end
