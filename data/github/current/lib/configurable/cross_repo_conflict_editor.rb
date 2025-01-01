# typed: true
# frozen_string_literal: true

module Configurable
  module CrossRepoConflictEditor

    extend T::Helpers
    requires_ancestor { Configurable }

    KEY = "cross_repo_conflict_editor_disabled"

    # Default is enabled
    # thus we need to delete the key to enable the setting
    def enable_cross_repo_conflict_editor(actor)
      config.delete(KEY, actor)
    end

    def disable_cross_repo_conflict_editor(actor)
      config.enable(KEY, actor)
    end

    # Default value is true
    def cross_repo_conflict_editor_enabled?
      !config.enabled?(KEY)
    end
  end
end
