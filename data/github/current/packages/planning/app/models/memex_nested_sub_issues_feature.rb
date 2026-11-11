# typed: strict
# frozen_string_literal: true

# Represents the feature of nested sub-issues in memex projects.
# This helper allows enabling the feature per user, per project, and per organization.
#
# Usage:
#   MemexNestedSubIssuesFeature.enabled?(project, actor: current_user)
#
# The feature checks from least to most specific:
#   1. Is it enabled for the project? If yes, return true.
#   2. Is the project in an organization AND is it enabled for that org? If yes, return true.
#   3. Is there an actor AND is it enabled for the actor/user? If yes, return true.
#   4. Otherwise, return false.
#
# This order allows logged-out users to access the feature if enabled at the project or org level,
# while still supporting user-level overrides where necessary.
#
module MemexNestedSubIssuesFeature
  extend T::Helpers

  MEMEX_NESTED_SUB_ISSUES_FLAG = :memex_nested_sub_issues
  INTERNAL_DEV_FLAG = :memex_nested_sub_issues_internal_dev

  # Check if nested sub-issues feature is enabled for a project and optional actor.
  #
  # project - The MemexProject to check.
  # actor   - The User to check. Optional - allows logged-out users if enabled at project/org level.
  #
  # Returns true if the feature is enabled at any level (project, org, or user).
  sig { params(project: MemexProject, actor: T.nilable(User)).returns(T::Boolean) }
  def self.enabled?(project, actor: nil)
    # 1. Check if enabled for the project
    return true if FeatureFlag.vexi.enabled?(MEMEX_NESTED_SUB_ISSUES_FLAG, project, default: false)

    # 2. Check if enabled for the organization (if project is org-owned)
    if project.owner.is_a?(Organization)
      return true if FeatureFlag.vexi.enabled?(MEMEX_NESTED_SUB_ISSUES_FLAG, project.owner, default: false)
    end

    # 3. Check if enabled for the actor/user
    return false unless actor
    FeatureFlag.vexi.enabled?(MEMEX_NESTED_SUB_ISSUES_FLAG, actor, default: false)
  end

  # Returns `true` if the internal feature flag is enabled. Used for checking if
  # internal, currently in-development features should be enabled for a user.
  sig { params(user: T.nilable(User)).returns(T::Boolean) }
  def self.enabled_internally_for_user?(user)
    FeatureFlag.vexi.enabled?(INTERNAL_DEV_FLAG, user, default: false)
  end
end
