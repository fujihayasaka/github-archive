# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::CopilotDiffChat
  class Loader
    MAX_DIFF_ENTRIES = 100

    class CopilotDiffChat < T::Struct
      const :base_owner_login, T.nilable(String)
      const :base_repository, T.nilable(Repository)
      const :entries, T::Array[GitHub::Diff::Entry]
      const :head_owner_login, T.nilable(String)
      const :head_repository, T.nilable(Repository)
    end

    sig do
      params(
        base_oid: T.nilable(String),
        head_oid: T.nilable(String),
        pull_request: PullRequest,
      ).returns(CopilotDiffChat)
    end
    def self.load(base_oid:, head_oid:, pull_request:)
      new(base_oid: base_oid, head_oid: head_oid, pull_request: pull_request).load
    end

    sig { returns(PullRequest) }
    attr_reader :pull_request

    sig { returns(T.nilable(String)) }
    attr_reader :base_oid

    sig { returns(T.nilable(String)) }
    attr_reader :head_oid

    sig do
      params(
        base_oid: T.nilable(String),
        head_oid: T.nilable(String),
        pull_request: PullRequest,
      ).void
    end
    def initialize(base_oid:, head_oid:, pull_request:)
      @base_oid = base_oid
      @head_oid = head_oid
      @pull_request = pull_request
    end

    sig { returns(CopilotDiffChat) }
    def load
      diff = pull_request.pull_comparison(
        start_oid: base_oid,
        end_oid: head_oid,
        base_oid: base_oid,
      )&.diff

      base_repository = pull_request.base_repository
      head_repository = pull_request.head_repository

      CopilotDiffChat.new(
        base_owner_login: base_repository&.owner_display_login,
        base_repository: pull_request.base_repository,
        entries: diff&.first(MAX_DIFF_ENTRIES) || [],
        head_owner_login: head_repository&.owner_display_login,
        head_repository: pull_request.head_repository,
      )
    end
  end
end
