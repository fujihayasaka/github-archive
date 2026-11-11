# typed: strict
# frozen_string_literal: true

# Shared logic for checking if a memex project feature flag is enabled.
#
# Memex feature flags follow a standard three-level check:
#   1. Is it enabled for the project? If yes, return true.
#   2. Is the project in an organization AND is it enabled for that org? If yes, return true.
#   3. Is there an actor AND is it enabled for the actor/user? If yes, return true.
#   4. Otherwise, return false.
#
# This order allows logged-out users to access the feature if enabled at the project or org level,
# while still supporting user-level overrides where necessary.
#
# Usage:
#   MemexProjectFeatureCheck.enabled?(:memex_agent_tasks, project, actor: current_user)
#
module MemexProjectFeatureCheck
  sig { params(flag: Symbol, project: T.nilable(MemexProject), actor: T.nilable(User)).returns(T::Boolean) }
  def self.enabled?(flag, project, actor: nil)
    return false if project.nil?

    # 1. Check if enabled for the project
    return true if FeatureFlag.vexi.enabled?(flag, project, default: false)

    # 2. Check if enabled for the organization (if project is org-owned)
    if project.owner.is_a?(Organization)
      return true if FeatureFlag.vexi.enabled?(flag, project.owner, default: false)
    end

    # 3. Check if enabled for the actor/user
    return false unless actor
    FeatureFlag.vexi.enabled?(flag, actor, default: false)
  end
end
