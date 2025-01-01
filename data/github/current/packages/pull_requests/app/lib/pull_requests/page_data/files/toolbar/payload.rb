# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::Files::Toolbar
  class Payload
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

    class PullRequestState < T::Enum
      enums do
        Open = new("OPEN")
        Merged = new("MERGED")
        Closed = new("CLOSED")
        Queued = new("QUEUED")
        Draft = new("DRAFT")
      end
    end

    class Author < T::Struct
      const :login, String
    end

    class Comparison < T::Struct
      const :baseOid, String
      const :headOid, String
    end

    class Repository < T::Struct
      const :id, Integer
      const :viewerPermission, String
    end

    class PullRequest < T::Struct
      const :aliveChannel, String
      # Shared with the header data, delete eventually
      const :author, Author
      const :comparison, Comparison
      const :id, String
      # This is the path of the pull request, e.g. `/test-user/test-repo/pull/1`
      const :pathName, String
      # Shared with the header data, delete eventually
      const :state, PullRequestState
      const :repository, Repository
      const :viewerAllowedNonCommentReviewTypes, T::Array[String]
      const :viewerIsCopilotAttributed, T::Boolean
      const :viewerHasViolatedPushPolicy, T::Boolean
    end

    class DiffViewSettings < T::Struct
      const :hideWhitespace, T::Boolean
      const :lineSpacing, String
      const :splitPreference, SplitPreference
      const :commentsPreference, CommentsPreference
    end

    class Toolbar < T::Struct
      const :annotations, T::Array[PullRequests::PageData::Annotations::Payload::Annotation]
      const :copilotAccessAllowed, T::Boolean
      const :currentUserLogin, T.nilable(String)
      const :isFileTreeExpanded, T::Boolean
      const :pullRequest, PullRequest
      const :shouldShowViewedFilesCount, T::Boolean
      const :totalFilesCount, Numeric
      const :viewedFilesCount, Numeric
      const :viewerPendingReview, T.nilable(PullRequests::PageData::Files::ReviewMenu::Payload::PendingReview)
      const :viewSettings, DiffViewSettings
    end

    sig do
      params(
        toolbar_data: PullRequests::PageData::Files::Toolbar::Loader::Data
      ).returns(Toolbar)
    end
    def self.call(toolbar_data)
      new.call(toolbar_data)
    end

    sig do
      params(
        toolbar_data: PullRequests::PageData::Files::Toolbar::Loader::Data
      ).returns(Toolbar)
    end
    def call(toolbar_data)
      repository = toolbar_data.pull_request.repository
      viewer_pending_review = toolbar_data.viewer_pending_review

      Toolbar.new(
        annotations: PullRequests::PageData::Annotations::Payload.call(toolbar_data.annotations),
        copilotAccessAllowed: toolbar_data.copilot_access_allowed,
        currentUserLogin: toolbar_data.current_user&.display_login,
        isFileTreeExpanded: toolbar_data.is_file_tree_expanded,
        pullRequest: PullRequest.new(
          aliveChannel: toolbar_data.pull_request.alive_channel,
          author: Author.new(
            login: toolbar_data.pull_request.author.display_login
          ),
          comparison: Comparison.new(
            baseOid: toolbar_data.pull_request.historical_comparison.base_oid,
            headOid: toolbar_data.pull_request.historical_comparison.head_oid
          ),
          id: toolbar_data.pull_request.id,
          pathName: toolbar_data.pull_request.path_name,
          repository: Repository.new(
            id: repository.id,
            viewerPermission: toolbar_data.pull_request.viewer_permission
          ),
          state: PullRequestState.deserialize(toolbar_data.pull_request.state.to_s.upcase),
          viewerAllowedNonCommentReviewTypes: toolbar_data.pull_request.viewer_allowed_non_comment_review_types.map(&:to_s),
          viewerIsCopilotAttributed: toolbar_data.pull_request.viewer_is_copilot_attributed,
          viewerHasViolatedPushPolicy: toolbar_data.pull_request.viewer_has_violated_push_policy
        ),
        shouldShowViewedFilesCount: toolbar_data.should_show_viewed_files_count,
        totalFilesCount: toolbar_data.total_files_count,
        viewedFilesCount: PullRequests::PageData::ViewedFilesCount::Payload.call(toolbar_data.viewed_files_count).viewedFilesCount,
        viewerPendingReview: PullRequests::PageData::Files::ReviewMenu::Payload.call(viewer_pending_review),
        viewSettings: DiffViewSettings.new(
          hideWhitespace: toolbar_data.view_settings.hide_whitespace,
          lineSpacing: toolbar_data.view_settings.line_spacing,
          splitPreference: SplitPreference.deserialize(toolbar_data.view_settings.split_preference.serialize),
          commentsPreference: CommentsPreference.deserialize(toolbar_data.view_settings.comments_preference.serialize),
        )
      )
    end
  end
end
