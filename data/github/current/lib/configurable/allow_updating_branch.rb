# typed: true
# frozen_string_literal: true

module Configurable
  module AllowUpdatingBranch
    KEY = "allow_update_branch".freeze

    extend T::Helpers
    extend Configurable::Async

    requires_ancestor { Configurable }

    include Instrumentation::Model

    def allow_updating_branches(force: false, actor:)
      instrument :change_merge_setting, {
        actor: actor,
        merge_setting: "update branch",
        enabled: true,
      }
      config.enable!(KEY, actor, force)
    end

    def disallow_updating_branches(force: true, actor:)
      instrument :change_merge_setting, {
        actor: actor,
        merge_setting: "update branch",
        enabled: false,
      }
      config.disable!(KEY, actor, force)
    end

    def enable_update_branch?
      config.enabled?(KEY)
    end
    async_configurable :enable_update_branch?
  end
end
