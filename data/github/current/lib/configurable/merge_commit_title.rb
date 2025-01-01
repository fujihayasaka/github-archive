# typed: true
# frozen_string_literal: true

# Configures the default merge commit title for the repository.
module Configurable
  module MergeCommitTitle
    include Kernel
    extend T::Helpers
    requires_ancestor { Configurable }

    KEY = "merge_commit_title".freeze

    PR_TITLE = "PR_TITLE".freeze
    MERGE_MESSAGE = "MERGE_MESSAGE".freeze

    VALUES = [PR_TITLE, MERGE_MESSAGE]

    def set_merge_commit_title_setting(setting:, actor:)
      raise ArgumentError unless VALUES.include?(setting)
      config.set(KEY, setting, actor)
    end

    def merge_commit_title_setting
      config.get(KEY) || MERGE_MESSAGE
    end

    def merge_commit_title_pr_title_enabled?
      merge_commit_title_setting == PR_TITLE
    end

    def merge_commit_title_merge_message_enabled?
      merge_commit_title_setting == MERGE_MESSAGE
    end
  end
end
