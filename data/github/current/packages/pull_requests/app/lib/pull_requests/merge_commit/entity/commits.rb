# typed: strict
# frozen_string_literal: true

module PullRequests
  module MergeCommit
    module Entity
      # Various states a merge/rebase commit can fall in to when computing mergeability.
      module Commits
        include Kernel
        extend T::Helpers
        extend T::Sig

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

      module Commits
        class Pending
          include Commits
        end

        class Skipped
          include Commits
        end

        class Found < T::Struct
          extend T::Sig

          include Commits

          const :sha, String
          const :base_sha, String
          const :head_sha, String

          sig { params(other_base_sha: String, other_head_sha: String).returns(T::Boolean) }
          def has_parents?(other_base_sha, other_head_sha)
            base_sha == other_base_sha && head_sha == other_head_sha
          end
        end

        class Created < T::Struct
          extend T::Sig

          include Commits

          const :sha, String
        end

        class Reused < T::Struct
          include Commits

          const :sha, String
        end

        class Conflict < T::Struct
          include Commits

          const :details, T::Hash[T.untyped, T.untyped]
        end

        class Invalid < T::Struct
          extend T::Sig

          include Commits

          sig { returns(Invalid) }
          def self.merge_commit_invalid
            new(reason: Enums::InvalidCommitReason::MergeCommitInvalid)
          end

          sig { returns(Invalid) }
          def self.merge_commit_conflict
            new(reason: Enums::InvalidCommitReason::MergeCommitConflict)
          end

          sig { returns(String) }
          def state_name
            "invalid|#{reason.serialize}"
          end

          const :reason, Enums::InvalidCommitReason
          const :code, T.nilable(Symbol)
        end
      end
    end
  end
end
