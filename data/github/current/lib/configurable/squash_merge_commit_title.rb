# typed: true
# frozen_string_literal: true

# Configures the default squash merge commit title for the repository.
module Configurable
  module SquashMergeCommitTitle
    include Kernel
    extend T::Helpers
    requires_ancestor { Configurable }

    KEY = "squash_merge_commit_title".freeze

    PR_TITLE = "PR_TITLE".freeze
    COMMIT_OR_PR_TITLE = "COMMIT_OR_PR_TITLE".freeze

    VALUES = [PR_TITLE, COMMIT_OR_PR_TITLE]

    def set_squash_merge_commit_title_setting(setting:, actor:)
      raise ArgumentError unless VALUES.include?(setting)
      config.set(KEY, setting, actor)
    end

    def squash_merge_commit_title_setting
      config.get(KEY) || COMMIT_OR_PR_TITLE
    end

    # Keeping this method for backwards compatibility, as the API still reflects this method.
    # It can be removed once all calls are switched over to the new helpers or the setting getter above.
    def squash_pr_title_enabled?
      squash_merge_commit_title_setting == PR_TITLE
    end

    def squash_merge_commit_title_pr_title_enabled?
      squash_merge_commit_title_setting == PR_TITLE
    end

    def squash_merge_commit_title_commit_pr_title_enabled?
      squash_merge_commit_title_setting == COMMIT_OR_PR_TITLE
    end
  end
end
