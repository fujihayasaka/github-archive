# typed: strict
# frozen_string_literal: true

# Configures whether to allow merge commits when merging a pull request for a repository
module Configurable
  module MergeCommits
    extend Configurable::Async

    extend T::Helpers
    include Kernel

    requires_ancestor { Configurable }

    KEY = "merge_commits_disabled"

    # Allow merge commits for repository.
    sig { params(actor: User).returns(T::Boolean) }
    def allow_merge_commits(actor:)
      config.delete(KEY, actor)
    end

    # Disallow merge commits for repository.
    sig { params(actor: User).returns(T::Boolean) }
    def disallow_merge_commits(actor:)
      config.enable(KEY, actor)
    end

    sig { returns(T::Boolean) }
    def merge_commits_allowed?
      !config.enabled?(KEY)
    end
    async_configurable :merge_commits_allowed?
  end
end
