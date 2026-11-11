# typed: true
# frozen_string_literal: true

# Configures the default squash merge commit message body for the repository.
module Configurable
  module SquashMergeCommitMessage
    include Kernel
    extend T::Helpers
    requires_ancestor { Configurable }

    KEY = "squash_merge_commit_message".freeze

    PR_BODY = "PR_BODY".freeze
    COMMIT_MESSAGES = "COMMIT_MESSAGES".freeze
    BLANK = "BLANK".freeze

    VALUES = [PR_BODY, COMMIT_MESSAGES, BLANK]

    def set_squash_merge_commit_message_setting(setting:, actor:)
      raise ArgumentError unless VALUES.include?(setting)
      config.set(KEY, setting, actor)
    end

    def squash_merge_commit_message_setting
      config.get(KEY) || COMMIT_MESSAGES
    end

    def squash_commit_message_pr_body_enabled?
      squash_merge_commit_message_setting == PR_BODY
    end

    def squash_commit_message_commit_messages_enabled?
      squash_merge_commit_message_setting == COMMIT_MESSAGES
    end

    def squash_commit_message_blank_enabled?
      squash_merge_commit_message_setting == BLANK
    end
  end
end
