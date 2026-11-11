# typed: true
# frozen_string_literal: true

module Configurable
  module AllowAutoDeletingBranches
    extend T::Helpers

    requires_ancestor { Configurable }
    requires_ancestor { Instrumentation::Model }

    KEY = "allow_auto_deleting_branches".freeze

    extend Configurable::Async

    def allow_auto_deleting_branches(force: false, actor:)
      instrument :change_merge_setting, {
        actor: actor,
        merge_setting: "auto-delete branches",
        enabled: true,
      }
      config.enable!(KEY, actor, force)
    end

    def disallow_auto_deleting_branches(force: true, actor:)
      instrument :change_merge_setting, {
        actor: actor,
        merge_setting: "auto-delete branches",
        enabled: false,
      }
      config.disable!(KEY, actor, force)
    end

    def delete_branch_on_merge?
      config.enabled?(KEY)
    end
    async_configurable :delete_branch_on_merge?
  end
end
