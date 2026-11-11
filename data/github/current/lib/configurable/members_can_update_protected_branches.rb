# typed: true
# frozen_string_literal: true

module Configurable
  module MembersCanUpdateProtectedBranches
    extend T::Helpers

    KEY = "disable_members_can_update_protected_branches".freeze

    requires_ancestor { Configurable }
    requires_ancestor { Instrumentation::Model }

    def disallow_members_can_update_protected_branches(force: false, actor:)
      changed = config.enable!(KEY, actor, force)
      return unless changed

      GitHub.dogstats.increment("members_can_update_protected_branches.disable")
      instrument("members_can_update_protected_branches.disable", { user: actor })
    end

    def allow_members_can_update_protected_branches(force: false, actor:)
      changed = if force
        config.disable!(KEY, actor, force)
      else
        config.delete(KEY, actor)
      end
      return unless changed

      GitHub.dogstats.increment("members_can_update_protected_branches.enable")
      instrument("members_can_update_protected_branches.enable", { user: actor })
    end

    def clear_members_can_update_protected_branches(actor:)
      changed = config.delete(KEY, actor)
      return unless changed

      GitHub.dogstats.increment("members_can_update_protected_branches.clear")
      instrument("members_can_update_protected_branches.clear", { user: actor })
    end

    def members_can_update_protected_branches?
      !config.enabled?(KEY)
    end

    def members_can_update_protected_branches_policy?
      !!config.final?(KEY)
    end
  end
end
