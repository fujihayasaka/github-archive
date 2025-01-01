# typed: true  # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Copilot
  class GetPullRequestCommitsResponse

    sig { params(pull_request: ::PullRequest, repository: ::Repository).void }
    def initialize(pull_request:, repository:)
      @pull_request = pull_request
      @repository = repository
    end

    def payload
      {
        commits: commits
      }
    end

    private

    sig { returns(::PullRequest) }
    attr_reader :pull_request

    sig { returns(::Repository) }
    attr_reader :repository

    def commits
      pull_request.changed_commits.map do |commit|
        {
          commit_oid: commit.oid,
          commit_msg: commit.message,
          author_name: commit.author_name,
          author_email: commit.author_email,
          author_login: commit.author&.display_login,
          permalink: commit.url,
          created_at: commit.committed_date,
          repo_name: repository.name,
          repo_id: repository.id,
          repo_owner: repository.owner_display_login,
          co_authors: co_authors(commit),
        }
      end
    end

    def co_authors(commit)
      co_author_names(commit: commit).map.with_index do |name, index|
        {
          name: name,
          email: co_author_emails(commit: commit)[index]
        }
      end
    end

    sig { params(commit: ::Commit).returns(T::Array[String]) }
    def co_author_names(commit:)
      commit.author_names.reject { |name| name == commit.author_name }
    end

    sig { params(commit: ::Commit).returns(T::Array[String]) }
    def co_author_emails(commit:)
      commit.author_emails.reject { |email| email == commit.author_email }
    end
  end
end
