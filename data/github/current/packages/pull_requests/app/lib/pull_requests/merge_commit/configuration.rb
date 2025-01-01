# typed: strict
# frozen_string_literal: true

module PullRequests
  module MergeCommit
    # Per-repository configuration for how the merge commit process executes.
    class Configuration < T::Struct
      extend T::Sig

      # Disable rebase commits in the whole process. Enabled for specific repositories who do not use rebase commits
      # and create very high system load.
      const :skip_rebase, T::Boolean

      # How many PRs to include in to the batch ref update.
      const :batch_size, Integer, default: 1

      # How long to wait for a rebase to timeout.
      const :rebase_timeout, Integer, default: 1

      sig { returns(T::Hash[String, T.untyped]) }
      def to_logging_h
        serialize.transform_keys! { |key| "gh.merge_commits.config.#{key}" }
      end
    end
  end
end
