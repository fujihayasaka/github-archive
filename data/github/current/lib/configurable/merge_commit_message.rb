# typed: true
# frozen_string_literal: true

# Configures the default merge commit message body for the repository.
module Configurable
  module MergeCommitMessage
    include Kernel
    extend T::Helpers
    requires_ancestor { Configurable }

    KEY = "merge_commit_message".freeze

    PR_BODY = "PR_BODY".freeze
    PR_TITLE = "PR_TITLE".freeze
    BLANK = "BLANK".freeze

    VALUES = [PR_BODY, PR_TITLE, BLANK]

    PR_BODY_OMISSION_STARTING_TAG = "<!-- Exclude from commit message -->"
    PR_BODY_OMISSION_ENDING_TAG = "<!-- End of exclude from commit message -->"

    def set_merge_commit_message_setting(setting:, actor:)
      raise ArgumentError unless VALUES.include?(setting)
      config.set(KEY, setting, actor)
    end

    def merge_commit_message_setting
      config.get(KEY) || PR_TITLE
    end

    def merge_commit_message_pr_body_enabled?
      merge_commit_message_setting == PR_BODY
    end

    def merge_commit_message_pr_title_enabled?
      merge_commit_message_setting == PR_TITLE
    end

    def merge_commit_message_blank_enabled?
      merge_commit_message_setting == BLANK
    end
  end
end
