# typed: strict
# frozen_string_literal: true

module PullRequests
  module MergeCommit
    module Entity
      # Various states a merge/rebase commit can fall in to when computing mergeability.
      module Commits
        include Kernel
        extend T::Helpers

        sealed!

        sig { returns(T::Boolean) }
        def reused?
          is_a?(Reused)
        end

        sig { returns(T::Boolean) }
        def skipped?
          is_a?(Skipped)
        end

        sig { returns(T::Boolean) }
        def pending?
          is_a?(Pending)
        end

        sig { returns(T::Boolean) }
        def conflict?
          is_a?(Conflict)
        end

        sig { returns(String) }
        def state_name
          self.class.name.demodulize.underscore
        end
      end

      # These classes indicate the concrete state a commit can be in.
      module Commits
        # No commit exists, and awaiting the generation of one.
        class Pending < T::Struct
          include Commits
        end

        # A commit exists matching one of the existing references to commits on a Pull Request. These include:
        #
        #   * pull.merge_commit_sha
        #   * pull.rebase_ref
        class Found < T::Struct
          include Commits

          const :sha, String

          # The parent head_sha and base_sha of a merge commit indicate which SHAs were used in the merge commit computation.
          const :base_sha, String
          const :head_sha, T.nilable(String)

          # Tree OID's are a representation of the git state without relevant commit data. Two commits that produce
          # idential git state will have identical tree OIDs, but different commit OIDs due to metadata about the commit
          # being included in the SHA.
          const :tree_sha, String

          const :created_at, Time
        end

        # A commit was created during the execution of the processor.
        class Created < T::Struct
          include Commits

          const :sha, String
        end

        # A commit that already existed and was validated to be reused, reducing compute usage but not duplicating commits.
        class Reused < T::Struct
          include Commits

          const :sha, String
        end

        # A commit that is still valid to be reused and falls within the set TTL,
        # reducing compute usage by not regenerating a new merge commit.
        class Cacheable < T::Struct
          include Commits

          const :sha, String
        end

        # A conflict in generating the specific commit.
        class Conflict < T::Struct
          include Commits

          const :details, T::Hash[T.untyped, T.untyped]
        end

        # Optional optimization for larger customers/repositories where the Rebase commit can be omitted to reduce load.
        class Skipped
          include Commits
        end

        class Ineligible
          include Commits
        end

        class Failed
          include Commits
        end

        class PendingDeletion
          include Commits
        end
      end
    end
  end
end
