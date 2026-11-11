# typed: strict
# frozen_string_literal: true

module CodeQuality
  class ProposedCommitsFilter
    sig { returns(T::Array[ProposedCommit]) }
    attr_reader :accepted_commits

    sig { returns(T::Array[ProposedCommit]) }
    attr_reader :rejected_commits

    sig { params(proposed_commits: T::Array[ProposedCommit]).void }
    def initialize(proposed_commits)
      @proposed_commits = proposed_commits
      @accepted_commits = T.let([], T::Array[ProposedCommit])
      @rejected_commits = T.let([], T::Array[ProposedCommit])
      @accepted_commits, @rejected_commits = filter_proposed_commits(@proposed_commits)
    end

    private

    sig { params(proposed_commit: ProposedCommit, accepted_commits: T::Array[ProposedCommit]).returns(T.nilable(ProposedCommit)) }
    def get_first_overlapping_commit(proposed_commit, accepted_commits)
      accepted_commits.find { |accepted_commit| accepted_commit != proposed_commit && proposed_commit.overlaps?(accepted_commit) }
    end

    # Assume that proposed_commits are sorted in reverse order by location
    sig { params(proposed_commits: T::Array[ProposedCommit]).returns([T::Array[ProposedCommit], T::Array[ProposedCommit]]) }
    def filter_proposed_commits(proposed_commits)
      accepted_commits = T.let([], T::Array[ProposedCommit])

      proposed_commits.each do |proposed_commit|
        overlapping_commit = get_first_overlapping_commit(proposed_commit, accepted_commits)

        # The proposed commit should be committed if there is no overlapping commit or it is later than the overlapping commit
        if overlapping_commit.nil? || proposed_commit.is_later_than?(overlapping_commit)
          accepted_commits << proposed_commit
        end
      end

      rejected_commits = proposed_commits - accepted_commits

      [accepted_commits, rejected_commits]
    end
  end
end
