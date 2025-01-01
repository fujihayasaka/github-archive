# typed: true
# frozen_string_literal: true

class PullRequest
  class ChangedFile
    attr_reader :path, :additions, :status, :deletions, :repository, :pull_request, :path_digest

    def initialize(path:, additions:, deletions:, status:, repository:, pull_request:)
      @path = path
      @status = status
      @additions = additions
      @deletions = deletions
      @repository = repository
      @pull_request = pull_request
      @path_digest = Digest::SHA256.hexdigest(path)
    end

    def async_repository
      Promise.resolve(repository)
    end

    def platform_type_name
      "PullRequestChangedFile"
    end
  end
end
