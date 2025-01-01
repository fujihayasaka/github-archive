# typed: strict
# frozen_string_literal: true

module PullRequests
  module HeadShas
    # Get head SHAs for pull requests in a repository.
    sig do
      params(
        repository_id: Integer,
        limit: Integer,
        offset: Integer
      ).returns(T::Array[String])
    end
    def self.for_repository(repository_id:, limit:, offset:)
      PullRequest.where(repository_id: repository_id)
                 .where.not(head_sha: nil)
                 .distinct
                 .order(:head_sha)
                 .limit(limit)
                 .offset(offset)
                 .pluck(:head_sha)
    end
  end
end
