# typed: strict
# frozen_string_literal: true

# Configures whether to allow rebase commits when merging pull requests for a repository
module Configurable
  module RebaseCommits
    extend Configurable::Async
    extend T::Sig
    extend T::Helpers
    include Kernel

    requires_ancestor { Configurable }

    KEY = "rebase_commits_disabled"

    # Allow rebase commits for repository.
    sig { params(actor: User).returns(T::Boolean) }
    def allow_rebase_commits(actor:)
      config.delete(KEY, actor)
    end

    # Disallow rebase commits for repository.
    sig { params(actor: User).returns(T::Boolean) }
    def disallow_rebase_commits(actor:)
      config.enable(KEY, actor)
    end

    sig { returns(T::Boolean) }
    def rebase_commits_allowed?
      !config.enabled?(KEY)
    end
    async_configurable :rebase_commits_allowed?
  end
end
