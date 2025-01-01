# typed: strict
# frozen_string_literal: true

module PullRequests::PageData
  class CommitsPayload
    include GitHub::Memoizer
    include GitHub::ResilienceMixin
    include Commits::ReactPayloadDataDependency

    COMMIT_GROUPS_FALLBACK = T.let([], T::Array[T.untyped])
    TRUNCATED_FALLBACK = false

    sig { returns(String) }
    attr_reader :current_path

    sig { returns(T.nilable(User)) }
    attr_reader :current_user

    sig { returns(PullRequest) }
    attr_reader :pull_request

    sig { returns(String) }
    attr_reader :tree_name

    sig do
      params(
        current_path: String,
        current_user: T.nilable(User),
        pull_request: PullRequest,
        tree_name: String
      ).returns(T::Hash[String, T.untyped])
    end
    def self.build(current_path:, current_user:, pull_request:, tree_name:)
      new(current_path:, current_user:, pull_request:, tree_name:).build
    end

    sig { params(current_path: String, current_user: T.nilable(User), pull_request: PullRequest, tree_name: String).void }
    def initialize(current_path:, current_user:, pull_request:, tree_name:)
      @current_path = current_path
      @current_user = current_user
      @pull_request = pull_request
      @tree_name = tree_name
    end

    sig { returns(T::Hash[String, T.untyped]) }
    def build
      # this will be removed in a future PR
      alive_channel = GitHub::WebSocket::Channels.signed_pull_request(pull_request)
      repository = T.must(pull_request.repository)
      deferred_commits_data_url = \
        Rails.application.routes.url_helpers.pull_requests_deferred_commits_data_path(
          id: pull_request.number,
          user_id: repository.owner_display_login,
          repository: repository.name,
        )
      time_out_message = ""
      truncated = T.let(false, T::Boolean)

      begin
        commit_groups = \
          build_grouped_commits_payload(pull_request.changed_commits, current_user, order: :asc, pull_request:)
        truncated = \
          with_database_error_fallback(fallback: TRUNCATED_FALLBACK) { T.must(pull_request.commit_limit_exceeded?) }
      rescue GitRPC::Timeout, Timeout::Error
        time_out_message = "git log #{tree_name}#{current_path}"
        commit_groups = COMMIT_GROUPS_FALLBACK
      end

      PullRequests::PageData::CommitsSerializer.new(
        alive_channel:,
        commit_groups:,
        deferred_commits_data_url:,
        repository:,
        time_out_message:,
        truncated:
      ).to_hash
    end

    private

    # Required for Commits::ReactPayloadDataDependency#build_grouped_commits_payload
    sig { returns(ActionView::Base) }
    memoize def view_context
      EmptyController.new.view_context
    end
  end
end
