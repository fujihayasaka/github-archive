# typed: strict
# frozen_string_literal: true

# Represents the feature of supporting Agent Tasks as a memex project item type.
# This helper allows enabling the feature per user, per project, and per organization.
#
# Usage:
#   MemexAgentTasksFeature.enabled?(project, actor: current_user)
#
# The feature checks from least to most specific:
#   1. Is it enabled for the project? If yes, return true.
#   2. Is the project in an organization AND is it enabled for that org? If yes, return true.
#   3. Is there an actor AND is it enabled for the actor/user? If yes, return true.
#   4. Otherwise, return false.
#
module MemexAgentTasksFeature
  extend T::Helpers

  PROJECTS_AGENT_TASKS_FLAG = :memex_agent_tasks

  # Check if Memex Agent Tasks feature is enabled for a project and optional actor.
  #
  # project - The MemexProject to check.
  # actor   - The User to check. Optional - allows logged-out users if enabled at project/org level.
  #
  # Returns true if the feature is enabled at any level (project, org, or user).
  sig { params(project: MemexProject, actor: T.nilable(User)).returns(T::Boolean) }
  def self.enabled?(project, actor: nil)
    # 1. Check if enabled for the project
    return true if FeatureFlag.vexi.enabled?(PROJECTS_AGENT_TASKS_FLAG, project, default: false)

    # 2. Check if enabled for the organization (if project is org-owned)
    if project.owner.is_a?(Organization)
      return true if FeatureFlag.vexi.enabled?(PROJECTS_AGENT_TASKS_FLAG, project.owner, default: false)
    end

    # 3. Check if enabled for the actor/user
    return false unless actor
    FeatureFlag.vexi.enabled?(PROJECTS_AGENT_TASKS_FLAG, actor, default: false)
  end
end
