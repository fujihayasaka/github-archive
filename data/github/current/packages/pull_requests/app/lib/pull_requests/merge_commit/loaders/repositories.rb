# typed: strict
# frozen_string_literal: true

module PullRequests
  module MergeCommit
    # Batch load Refs by Repository.
    module Loaders
      class Repositories
        sig { params(pull_request: PullRequest, repository: Repository).void }
        def initialize(pull_request:, repository:)
          @pull_request = pull_request
          @repository = repository
        end

        sig { returns(T.nilable(Repository)) }
        def base_repository
          if @repository.advisory_workspace?
            @repository.parent_advisory_repository
          else
            @pull_request.base_repository
          end
        end

        sig { returns(T.nilable(Repository)) }
        def head_repository
          if @repository.advisory_workspace?
            @repository
          else
            @pull_request.head_repository
          end
        end
      end
    end
  end
end
