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

    class CommentsPreference < T::Enum
      enums do
        # TODO we should update these values to be UPCASE to match ENUMS elsewhere in PullRequests code, but that requires client code changes.
        # discussion link https://github.com/github/pull-requests/discussions/9767#discussioncomment-9885181 which led to doing this for all ENUMs
        Visible = new(UserSettings::DIFF_COMMENTS_PREFERENCES[0])
        Collapsed = new(UserSettings::DIFF_COMMENTS_PREFERENCES[1])
      end
    end

    class AllowedNonCommentReviewType < T::Enum
      enums do
        APPROVE = new("APPROVE")
        REQUEST_CHANGES = new("REQUEST_CHANGES")
      end
    end

    class CommentingSettings < T::Struct
      const :emoji_skin_tone_preference, Integer
      const :paste_url_link_as_plain_text, T::Boolean
      const :use_monospace_font, T::Boolean
    end

    class Comparison < T::Struct
      const :base_oid, String
      const :head_oid, String
    end

    class PullRequest < T::Struct
      const :alive_channel, String
      const :author, User
      const :historical_comparison, Comparison
      const :id, String
      const :path_name, String
      const :repository, Repository
      const :state, ::PullRequest::Icon::State
      const :viewer_allowed_non_comment_review_types, T::Array[AllowedNonCommentReviewType]
      const :viewer_can_leave_non_comment_reviews, T::Boolean
      const :viewer_has_violated_push_policy, T::Boolean
      const :viewer_is_copilot_attributed, T::Boolean
      const :viewer_can_apply_suggestion, T::Boolean
      const :viewer_permission, String
    end

    class DiffViewSettings < T::Struct
      const :hide_whitespace, T::Boolean
      const :line_spacing, String
      const :split_preference, SplitPreference
      const :comments_preference, CommentsPreference
    end

    class Data < T::Struct
      const :annotations, T::Array[PullRequests::PageData::Annotations::Loader::Annotation]
      const :commenting_settings, CommentingSettings
      const :copilot_access_allowed, T::Boolean
      const :current_user, T.nilable(User)
      const :is_file_tree_expanded, T::Boolean
      const :pull_request, PullRequest
      const :should_show_viewed_files_count, T::Boolean
      const :thread_previews, T::Array[PullRequests::PageData::ThreadPreviews::Loader::ThreadPreview]
      const :total_files_count, Numeric
      const :viewed_files_count, Numeric
      const :viewer_pending_review, PullRequests::PageData::Files::ReviewMenu::Loader::PendingReview
      const :view_settings, DiffViewSettings
    end

    sig do
      params(
        cap_filter: T.nilable(ConditionalAccess::Web::Filter),
        comparison: ::PullRequest::Comparison,
        current_user: T.nilable(User),
        end_commit_oid: String,
        pull_request: ::PullRequest,
        user_session: T.nilable(UserSession),
        limit_config: PullRequests::PageData::Files::PageLimitConfig,
        paths: T.nilable(T::Array[String]) # Optional paths to filter annotations
      ).returns(Data)
    end
    def self.load(cap_filter:, comparison:, current_user:, end_commit_oid:, pull_request:, user_session:, limit_config:, paths:)
      new(cap_filter:, comparison:, current_user:, end_commit_oid:, pull_request:, user_session:, limit_config:, paths:).load
    end

    sig do
      params(
        cap_filter: T.nilable(ConditionalAccess::Web::Filter),
        comparison: ::PullRequest::Comparison,
        current_user: T.nilable(User),
        end_commit_oid: String,
        pull_request: ::PullRequest,
        user_session: T.nilable(UserSession),
        limit_config: PullRequests::PageData::Files::PageLimitConfig,
        paths: T.nilable(T::Array[String])
      ).void
    end
    def initialize(cap_filter:, comparison:, current_user:, end_commit_oid:, pull_request:, user_session:, limit_config:, paths:)
      @comparison = comparison
      @current_user = current_user
      @end_commit_oid = end_commit_oid
      @pull_request = pull_request
      @user_session = user_session
      @cap_filter = cap_filter
      @limit_config = limit_config
      @paths = paths
    end

    sig { returns(Data) }
    def load
      Data.new(
        annotations: PullRequests::PageData::Annotations::Loader.load(
          current_user: @current_user,
          pull_request: @pull_request,
          user_session: @user_session,
          end_commit_oid: @end_commit_oid,
          limit_config: @limit_config,
          paths: @paths || []
        ),
        commenting_settings: CommentingSettings.new(
          emoji_skin_tone_preference: @current_user&.profile_settings&.preferred_emoji_skin_tone || 0,
          paste_url_link_as_plain_text: @current_user&.paste_url_link_as_plain_text? || false,
          use_monospace_font: @current_user&.use_fixed_width_font? || false,
        ),
        copilot_access_allowed: copilot_access_allowed?,
        current_user: @current_user,
        is_file_tree_expanded: is_file_tree_expanded,
        pull_request: PullRequest.new(
          alive_channel: GitHub::WebSocket::Channels.signed_pull_request(@pull_request),
          author: @pull_request.safe_user,
          historical_comparison: Comparison.new(
            base_oid: @pull_request.historical_comparison.async_base_oid.sync,
            head_oid: @pull_request.historical_comparison.async_head_oid.sync
          ),
          id: @pull_request.global_relay_id,
          path_name: T.must(@pull_request.permalink(include_host: false)),
          repository: T.must(@pull_request.repository),
          state: pull_request_state,
          viewer_allowed_non_comment_review_types: viewer_allowed_non_comment_review_types,
          viewer_can_leave_non_comment_reviews: viewer_can_leave_non_comment_reviews,
          viewer_has_violated_push_policy: @pull_request.user_has_violated_push_rule?(@current_user) || false,
          viewer_is_copilot_attributed: @pull_request.is_copilot_co_author?(@current_user) || false,
          viewer_can_apply_suggestion: @pull_request.suggested_change_applicable_by?(@current_user),
          viewer_permission: repository_viewer_permission
        ),
        should_show_viewed_files_count: @current_user.present? && @comparison.current?,
        thread_previews: PullRequests::PageData::ThreadPreviews::Loader.load(
          cap_filter: @cap_filter,
          current_user: @current_user,
          pull_request: @pull_request,
          limit_config: @limit_config,
        ),
        total_files_count: total_files_count,
        viewed_files_count: PullRequests::PageData::ViewedFilesCount::Loader.load(
          comparison: @comparison,
          current_user: @current_user,
          pull_request: @pull_request
        ),
        viewer_pending_review: PullRequests::PageData::Files::ReviewMenu::Loader.load(
          current_user: @current_user,
          pull_request: @pull_request
        ),
        view_settings: DiffViewSettings.new(
          hide_whitespace: ignore_whitespace,
          line_spacing: line_spacing,
          split_preference: split_preference,
          comments_preference: comments_preference
        )
      )
    end

    private

    sig { returns(Numeric) }
    def total_files_count
      total_files_count = CHANGED_FILES_COUNT_FALLBACK
      begin
        total_files_count = @comparison.changed_files
      rescue GitRPC::Error => error
        Failbot.report error
      end
    end

    sig { returns(T::Boolean) }
    def is_file_tree_expanded
      return true if @current_user.nil?

      with_database_error_fallback(fallback: true) do
        @current_user.settings.get(:pull_request_file_tree_visible)
      end
    end

    sig { returns(::PullRequest::Icon::State) }
    def pull_request_state
      # TODO remove db usage in the fallback
      state = with_database_error_fallback(fallback: ::PullRequest::Icon::State.deserialize(@pull_request.state)) do
        ::PullRequest::Icon::State.for_pull_request(@pull_request) || ::PullRequest::Icon::State::Open
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

    sig { returns(CommentsPreference) }
    def comments_preference
      @current_user.present? ? CommentsPreference.deserialize(@current_user.settings.get(:diff_comments_preference)) : CommentsPreference::Visible
    end

    sig { returns(T::Boolean) }
    def viewer_can_leave_non_comment_reviews
      return false unless @current_user.present?

      with_database_error_fallback(fallback: false) do
        @pull_request.allows_non_comment_reviews_from?(reviewer: @current_user)
      end
    end

    sig { returns(T::Array[AllowedNonCommentReviewType]) }
    def viewer_allowed_non_comment_review_types
      return [] unless @current_user.present?

      with_database_error_fallback(fallback: []) do
        @pull_request.allowed_non_comment_review_types_for(reviewer: @current_user).map do |review_type|
          AllowedNonCommentReviewType.deserialize(review_type.to_s.upcase)
        end
      end
    end

    sig { returns(T::Boolean) }
    def copilot_access_allowed?
      with_database_error_fallback(fallback: false) do
        !!@current_user&.feature_enabled?(:copilot_workspace)
      end
    end

    sig { returns(String) }
    def repository_viewer_permission
      return "read" unless @current_user.present?

      with_database_error_fallback(fallback: "read") do
        @pull_request.repository&.role_based_access_level(@current_user).to_s || "read"
      end
    end
  end
end
