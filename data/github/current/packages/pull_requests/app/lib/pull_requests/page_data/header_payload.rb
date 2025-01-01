# typed: strict
# frozen_string_literal: true

module PullRequests::PageData
  class HeaderPayload
    include GitHub::ResilienceMixin
    include CurrentRepositoryInteractionsHelper

    COMMITS_COUNT_FALLBACK = 0
    CURRENT_USER_CAN_CHANGE_BASE_FALLBACK = false
    CURRENT_USER_CAN_EDIT_TITLE_FALLBACK = false
    IS_IN_ADVISORY_REPO_FALLBACK = false

    sig { returns(T.nilable(User)) }
    attr_reader :current_user

    sig { returns(PullRequest) }
    attr_reader :pull_request

    sig do
      params(
        current_user: T.nilable(User),
        pull_request: PullRequest,
      ).returns(T::Hash[String, T.untyped])
    end
    def self.build(current_user:, pull_request:)
      new(current_user:, pull_request:).build
    end

    sig { params(current_user: T.nilable(User), pull_request: PullRequest).void }
    def initialize(current_user:, pull_request:)
      @current_user = current_user
      @pull_request = pull_request
    end

    sig { returns(T::Hash[String, T.untyped]) }
    def build
      banners_data = PullRequests::PageData::BannersDataPayload.build(
        current_user: @current_user,
        pull_request: @pull_request,
        repository: current_repository,
      )
      commit_count = COMMITS_COUNT_FALLBACK

      author_display_login = pull_request.safe_user.display_login
      base_url = pull_request.permalink(include_host: false)
      base_repository_default_branch = current_repository.default_branch
      head_repository = pull_request.head_repository
      head_owner = head_repository.nil? ? pull_request.head_user : head_repository.owner
      merged_by = pull_request.merged_by&.display_login
      merged_time = pull_request.merged_at&.iso8601&.to_s
      summary_diff = pull_request.historical_comparison.async_diff(summary: true).sync

      begin
        commit_count = pull_request.historical_comparison.total_commits
        lines_added = summary_diff.additions
        lines_deleted = summary_diff.deletions
        lines_changed = summary_diff.changes
      rescue GitRPC::Error => error
        Failbot.report error
      end

      current_user_can_change_base = \
        with_database_error_fallback(fallback: CURRENT_USER_CAN_CHANGE_BASE_FALLBACK) do
          pull_request.can_change_base_branch? && T.must(pull_request.issue).can_modify?(current_user)
        end

      current_user_can_edit_title = \
        with_database_error_fallback(fallback: CURRENT_USER_CAN_EDIT_TITLE_FALLBACK) do
          current_user_can_push?
        end

      is_in_advisory_repo = \
        with_database_error_fallback(fallback: IS_IN_ADVISORY_REPO_FALLBACK) do
          T.must(pull_request.in_advisory_workspace?)
        end

      pull_request_display_state = \
        with_database_error_fallback(fallback: pull_request.state.to_s) do
          PullRequest::Icon::State.for_pull_request(pull_request).to_s
        end

      codespaces_enabled = \
        with_database_error_fallback(fallback: false) do
          !!current_user&.codespaces_feature_enabled?
        end

      copilot_enabled = \
        with_database_error_fallback(fallback: false) do
          !!current_user&.feature_enabled?(:copilot_workspace)
        end

      editor_enabled = \
        with_database_error_fallback(fallback: false) do
          !!current_user&.workspace_editor_preview_enabled?(repository: current_repository)
        end

      PullRequests::PageData::HeaderSerializer.new(
        author_display_login:,
        banners_data:,
        base_repository: current_repository,
        base_repository_default_branch:,
        base_url:,
        codespaces_enabled:,
        commit_count:,
        copilot_enabled:,
        current_user_can_change_base:,
        current_user_can_edit_title:,
        editor_enabled:,
        head_owner:,
        head_repository:,
        is_enterprise: GitHub.enterprise?,
        is_in_advisory_repo:,
        lines_added:,
        lines_changed:,
        lines_deleted:,
        merged_by:,
        merged_time:,
        pull_request:,
        pull_request_display_state:,
      ).to_hash
    end

    private

    sig { returns(Repository) }
    def current_repository
      T.must(pull_request.repository)
    end
  end
end
