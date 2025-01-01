# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::Files::Toolbar
  class Loader
    include GitHub::ResilienceMixin

    CHANGED_FILES_COUNT_FALLBACK = 0

    class SplitPreference < T::Enum
      enums do
        # TODO we should update these values to be UPCASE to match ENUMS elsewhere in PullRequests code, but that requires client code changes.
        # discussion link https://github.com/github/pull-requests/discussions/9767#discussioncomment-9885181 which led to doing this for all ENUMs
        Split = new("split")
        Unified = new("unified")
      end
    end

    class PullRequest < T::Struct
      const :id, Integer
      const :path_name, String
    end

    class DiffViewSettings < T::Struct
      const :hide_whitespace, T::Boolean
      const :line_spacing, String
      const :split_preference, SplitPreference
    end

    class Data < T::Struct
      const :annotations, T::Array[PullRequests::PageData::Annotations::Loader::Annotation]
      const :host_url, String
      const :thread_previews, T::Array[PullRequests::PageData::ThreadPreviews::Loader::ThreadPreview]
      const :pull_request, PullRequest
      const :repository_id, Numeric
      const :total_files_count, Numeric
      const :viewed_files_count, Numeric
      const :view_settings, DiffViewSettings
    end

    sig do
      params(
        cap_filter: T.nilable(ConditionalAccess::Web::Filter),
        current_user: T.nilable(User),
        end_commit_oid: String,
        pull_request: ::PullRequest,
        user_session: T.nilable(UserSession),
      ).returns(Data)
    end
    def self.load(cap_filter:, current_user:, end_commit_oid:, pull_request:, user_session:)
      new(cap_filter:, current_user:, end_commit_oid:, pull_request:, user_session:).load
    end

    sig do
      params(
        cap_filter: T.nilable(ConditionalAccess::Web::Filter),
        current_user: T.nilable(User),
        end_commit_oid: String,
        pull_request: ::PullRequest,
        user_session: T.nilable(UserSession),
      ).void
    end
    def initialize(cap_filter:, current_user:, end_commit_oid:, pull_request:, user_session:)
      @current_user = current_user
      @end_commit_oid = end_commit_oid
      @pull_request = pull_request
      @user_session = user_session
      @cap_filter = cap_filter
    end

    sig { returns(Data) }
    def load
      Data.new(
        annotations: PullRequests::PageData::Annotations::Loader.load(
          current_user: @current_user,
          pull_request: @pull_request,
          user_session: @user_session,
          end_commit_oid: @end_commit_oid
        ),
        host_url: GitHub.url,
        pull_request: PullRequest.new(
          id: @pull_request.id,
          path_name: T.must(@pull_request.permalink(include_host: false))
        ),
        repository_id: @pull_request.repository_id,
        thread_previews: PullRequests::PageData::ThreadPreviews::Loader.load(
          cap_filter: @cap_filter,
          current_user: @current_user,
          pull_request: @pull_request
        ),
        total_files_count: total_files_count,
        viewed_files_count: PullRequests::PageData::ViewedFilesCount::Loader.load(
          current_user: @current_user,
          pull_request: @pull_request
        ),
        view_settings: DiffViewSettings.new(
          hide_whitespace: ignore_whitespace,
          line_spacing: line_spacing,
          split_preference: split_preference
        )
      )
    end

    private

    sig { returns(Numeric) }
    def total_files_count
      total_files_count = CHANGED_FILES_COUNT_FALLBACK
      begin
        total_files_count = @pull_request.changed_files
      rescue GitRPC::Error => error
        Failbot.report error
      end
    end

    sig { returns(T::Boolean) }
    def ignore_whitespace
      with_database_error_fallback(fallback: false) do
        @current_user.present? ? @pull_request.ignore_whitespace?(@current_user) : false
      end
    end

    sig { returns(String) }
    def line_spacing
      @current_user.present? ? @current_user.settings.get(:diff_line_spacing) : "relaxed"
    end

    sig { returns(SplitPreference) }
    def split_preference
      @current_user.present? && @current_user.split_diff_preferred ? SplitPreference::Split : SplitPreference::Unified
    end
  end
end
