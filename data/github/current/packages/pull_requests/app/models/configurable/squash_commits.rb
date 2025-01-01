# typed: strict
# frozen_string_literal: true

# Configures whether to allow squash commits when merging a pull request for a repository
module Configurable
  module SquashCommits
    extend Configurable::Async
    extend T::Sig
    extend T::Helpers
    include Kernel

    requires_ancestor { Configurable }

    KEY = "squash_commits_disabled"

    # Allow squash commits for repository.
    sig { params(actor: User).returns(T::Boolean) }
    def allow_squash_commits(actor:)
      config.delete(KEY, actor)
    end

    # Disallow squash commits for repository.
    sig { params(actor: User).returns(T::Boolean) }
    def disallow_squash_commits(actor:)
      config.enable(KEY, actor)
    end

    sig { returns(T::Boolean) }
    def squash_commits_allowed?
      !config.enabled?(KEY)
    end
    async_configurable :squash_commits_allowed?
  end
end
