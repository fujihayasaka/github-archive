# typed: strict
# frozen_string_literal: true

module PullRequests
  module MergeCommit
    module CreateStackedCommits
      class Loader
        include GitHub::Memoizer

        sig { params(stack: PullRequests::Stack, repository: Repository, priority: Integer).void }
        def initialize(stack:, repository:, priority: 0)
          @stack = stack
          @repository = repository
          @priority = priority
        end

        # Load a CreateCommits::Request for each PR in the stack, ordered bottom-up
        # (position ASC). Stops on the first PR that produces an invalid request,
        # since subsequent PRs depend on its merge commit.
        sig { returns(T::Array[CreateCommits::Request]) }
        memoize def requests
          requests = T.let([], T::Array[CreateCommits::Request])
          pull_requests = entries.filter_map(&:pull_request)

          # Grab the leading stack entries that are merged or in the queue, these aren't eligible for new merge commits.
          ineligible_pull_requests = pull_requests.take_while { _1.merged? || _1.in_merge_queue? }

          # Determine the state of the "active base" of the stack.
          if tail = ineligible_pull_requests.last
            if tail.merged?
              # If we're merged, use nil so it looks at the PR's base branch.
              base_branch_sha = nil
            elsif tail.in_merge_queue?
              # In the merge queue, the last known merge_commit_sha is valid until this PR merges.
              base_branch_sha = tail.merge_commit_sha
            end
          end

          (pull_requests - ineligible_pull_requests).each_with_index do |pull_request, i|
            # Skip over merged PRs in the stack as they're never valid for CPRMC.
            next if pull_request.merged?

            # TODO: This introduces a N+1, but will require rewriting the loader to be multiple PR aware.
            loader = CreateCommits::Loader.new(
              pull_request:,
              repository: @repository,
              priority: @priority,
              base_branch_sha: (base_branch_sha if i.zero?)
            )

            case request = loader.request
            when CreateCommits::Request
              requests << request
            when Enums::InvalidRequestReason
              break
            end
          end

          requests
        end

        sig { returns(T::Array[PullRequest]) }
        memoize def pull_requests = entries.map(&:pull_request).compact

        sig { returns(Integer) }
        def rebase_timeout
          ENV["REBASE_TIMEOUT_SECONDS"]&.to_i ||
            (FeatureFlag.vexi.enabled?(:rebase_timeout_1sec, default: false) ? 1 : 7)
        end

        private

        sig { returns(T::Array[PullRequests::StackEntry]) }
        memoize def entries = @stack.entries.order(position: :asc).includes(:pull_request).to_a
      end
    end
  end
end
