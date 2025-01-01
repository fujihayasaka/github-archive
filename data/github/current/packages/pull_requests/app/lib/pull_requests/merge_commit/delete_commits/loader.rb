# typed: strict
# frozen_string_literal: true

module PullRequests
  module MergeCommit
    module DeleteCommits
      class Loader
        include GitHub::Memoizer

        sig { params(pull_request: PullRequest, repository: Repository).void }
        def initialize(pull_request:, repository:)
          @pull_request = pull_request
          @repository = repository
        end

        sig { returns(T.any(Request, Enums::InvalidRequestReason)) }
        def request
          unless base_repository = repositories.base_repository
            return Enums::InvalidRequestReason::MissingBaseRepository
          end

          unless head_repository = repositories.head_repository
            return Enums::InvalidRequestReason::MissingHeadRepository
          end

          refs.request(base_repository, @pull_request.qualified_base_ref_name)
          refs.request(head_repository, @pull_request.qualified_head_ref_name)

          Request.new(
            pull_request_id: @pull_request.id.to_i,
            base_branch_sha: refs.read(base_repository, @pull_request.qualified_base_ref_name).to_s,
            head_branch_sha: refs.read(head_repository, @pull_request.qualified_head_ref_name).to_s,
            base_repository_id: base_repository.id.to_i,
            head_repository_id: head_repository.id.to_i,
          )
        end

        private

        sig { returns(Loaders::Repositories) }
        memoize def repositories
          Loaders::Repositories.new(pull_request: @pull_request, repository: @repository)
        end

        sig { returns(Loaders::Refs) }
        memoize def refs = Loaders::Refs.new
      end
    end
  end
end
