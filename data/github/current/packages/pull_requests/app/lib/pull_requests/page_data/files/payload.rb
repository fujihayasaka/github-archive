# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::Files
  class Payload
    class BaseRef < T::Struct
      const :branch, String
      const :defaultBranch, String
      const :isInAdvisoryRepo, T::Boolean
      const :oid, String
      const :repositoryId, String
      const :repositoryName, String
      const :repositoryOwnerLogin, String
    end

    class HeadRef < T::Struct
      const :branch, String
      const :oid, String
      const :repositoryName, String
      const :repositoryOwnerLogin, String
    end

    class PullRequestData < T::Struct
      const :author, T::Hash[String, String]
      const :baseBranch, String
      const :commitsCount, Integer
      const :comparison, PullRequests::PageData::Files::Toolbar::Payload::Comparison
      const :globalRelayId, String
      const :headBranch, String
      const :headRepositoryName, T.nilable(String)
      const :headRepositoryOwnerLogin, T.nilable(String)
      const :isInAdvisoryRepo, T::Boolean
      const :mergedBy, T.nilable(String)
      const :mergedTime, T.nilable(String)
      const :number, Integer
      const :pathName, String
      const :state, String
      const :title, String
      const :titleHtml, String
      const :viewerCanLeaveNonCommentReviews, T::Boolean
      const :viewerHasViolatedPushPolicy, T::Boolean
    end

    class Repository < T::Struct
      const :codespacesEnabled, T::Boolean
      const :copilotEnabled, T::Boolean
      const :editorEnabled, T::Boolean
      const :defaultBranch, String
      const :id, Integer
      const :isEnterprise, T::Boolean
      const :name, String
      const :ownerLogin, String
      const :viewerPermission, String
    end

    class User < T::Struct
      const :canChangeBase, T::Boolean
      const :currentUserLogin, T.nilable(String)
      const :canEditTitle, T::Boolean
      const :isFileTreeExpanded, T::Boolean
      const :lastReviewOid, T.nilable(String)
      const :shouldShowViewedFilesCount, T::Boolean
      const :viewedFilesCount, Numeric
      const :viewSettings, PullRequests::PageData::Files::Toolbar::Payload::DiffViewSettings
    end

    class UrlsData < T::Struct
      const :checks, String
      const :commits, String
      const :conversation, T.nilable(String)
      const :files, String
      const :walkthrough, String
    end

    class Payload < T::Struct
      const :aliveChannel, String
      const :annotations, T::Array[PullRequests::PageData::Annotations::Payload::Annotation]
      const :bannersData, T::Hash[String, T::Hash[String, T::Hash[String, Object]]]
      const :commits, T::Array[PullRequests::PageData::Files::FileTree::Payload::Commit]
      const :diffSummaries, T::Array[PullRequests::PageData::Files::FileTree::Payload::Diff]
      const :diffContents, T::Array[PullRequests::PageData::Diffs::Contents::Payload::Entry]
      const :pullRequest, PullRequestData
      const :repository, Repository
      const :threadPreviews, T::Array[PullRequests::PageData::ThreadPreviews::Payload::ThreadPreview]
      const :urls, UrlsData
      const :user, User
      const :viewerPendingReview, T.nilable(PullRequests::PageData::Files::ReviewMenu::Payload::PendingReview)
    end

    sig do
      params(loader_data: PullRequests::PageData::Files::Loader::Data).returns(Payload)
    end
    def self.call(loader_data)
      new.call(loader_data)
    end

    sig do
      params(loader_data: PullRequests::PageData::Files::Loader::Data).returns(Payload)
    end
    def call(loader_data)
      header_data = loader_data.header
      toolbar_data = loader_data.toolbar
      file_tree_data = loader_data.file_tree
      diff_contents_data = loader_data.diff_contents

      annotations_payload = PullRequests::PageData::Annotations::Payload.new

      annotations = annotations_payload.call(toolbar_data.annotations)
      annotation_levels = annotations_payload.payload_annotations_highest_level(annotations)

      diff_contents_payload = PullRequests::PageData::Diffs::Contents::Payload.new
      diff_contents = diff_contents_payload.call(diff_contents_data)

      Payload.new(
        aliveChannel: header_data["aliveChannel"],
        annotations: annotations,
        bannersData: header_data["bannersData"],
        commits: file_tree_data.commits.map do |commit|
          PullRequests::PageData::Files::FileTree::Payload::Commit.new(
            actorLogin: commit.user_display_login,
            createdAt: commit.created_at.to_s,
            messageHeadline: commit.short_message_text,
            oid: commit.oid,
            shortOid: commit.abbreviated_oid
          )
        end,
        diffSummaries: file_tree_data.diffs.map do |diff|
          PullRequests::PageData::Files::FileTree::Payload::Diff.new(
            changeType: Diffs::Entry::ChangeType.deserialize(diff.diff_delta.status_label&.upcase),
            isCodeowner: diff.is_codeowner,
            isManifestFile: DependencyManifestFile.recognized_path?(path: diff.diff_delta.path),
            isVendored: diff.tree_entry.vendored?,
            markedAsViewed: file_tree_data.viewed_files.reviewed?(diff.diff_delta.path),
            path: diff.diff_delta.path,
            pathDigest: Digest::SHA256.hexdigest(diff.diff_delta.path),
            highestAnnotationLevel: annotation_levels[diff.diff_delta.path],
            totalCommentsCount: file_tree_data.thread_previews[diff.diff_delta.path],
          )
        end,
        diffContents: diff_contents,
        pullRequest: PullRequestData.new(
          author: header_data["pullRequest"]["author"],
          baseBranch: header_data["pullRequest"]["baseBranch"],
          commitsCount: header_data["pullRequest"]["commitsCount"],
          comparison: PullRequests::PageData::Files::Toolbar::Payload::Comparison.new(
            baseOid: toolbar_data.pull_request.historical_comparison.base_oid,
            headOid: toolbar_data.pull_request.historical_comparison.head_oid
          ),
          globalRelayId: header_data["pullRequest"]["relayId"],
          headBranch: header_data["pullRequest"]["headBranch"],
          headRepositoryName: header_data["pullRequest"]["headRepositoryName"],
          headRepositoryOwnerLogin: header_data["pullRequest"]["headRepositoryOwnerLogin"],
          isInAdvisoryRepo: header_data["pullRequest"]["isInAdvisoryRepo"],
          mergedBy: header_data["pullRequest"]["mergedBy"],
          mergedTime: header_data["pullRequest"]["mergedTime"],
          number: header_data["pullRequest"]["number"],
          pathName: toolbar_data.pull_request.path_name,
          state: header_data["pullRequest"]["state"],
          title: header_data["pullRequest"]["title"],
          titleHtml: header_data["pullRequest"]["titleHtml"],
          viewerCanLeaveNonCommentReviews: toolbar_data.pull_request.viewer_can_leave_non_comment_reviews,
          viewerHasViolatedPushPolicy: toolbar_data.pull_request.viewer_has_violated_push_policy,
        ),
        repository: Repository.new(
          codespacesEnabled: header_data["repository"]["codespacesEnabled"],
          copilotEnabled: header_data["repository"]["copilotEnabled"],
          editorEnabled: header_data["repository"]["editorEnabled"],
          defaultBranch: header_data["repository"]["defaultBranch"],
          id: header_data["repository"]["id"],
          isEnterprise: header_data["repository"]["isEnterprise"],
          name: header_data["repository"]["name"],
          ownerLogin: header_data["repository"]["ownerLogin"],
          viewerPermission: toolbar_data.pull_request.viewer_permission
        ),
        user: User.new(
          canChangeBase: header_data["user"]["canChangeBase"],
          currentUserLogin: toolbar_data.current_user&.display_login,
          canEditTitle: header_data["user"]["canEditTitle"],
          isFileTreeExpanded: toolbar_data.is_file_tree_expanded,
          lastReviewOid: file_tree_data.last_review_oid,
          shouldShowViewedFilesCount: toolbar_data.should_show_viewed_files_count,
          viewedFilesCount: toolbar_data.viewed_files_count,
          viewSettings: PullRequests::PageData::Files::Toolbar::Payload::DiffViewSettings.new(
            hideWhitespace: toolbar_data.view_settings.hide_whitespace,
            lineSpacing: toolbar_data.view_settings.line_spacing,
            splitPreference: PullRequests::PageData::Files::Toolbar::Payload::SplitPreference.deserialize(toolbar_data.view_settings.split_preference.serialize),
            commentsPreference: PullRequests::PageData::Files::Toolbar::Payload::CommentsPreference.deserialize(toolbar_data.view_settings.comments_preference.serialize),
          )
        ),
        threadPreviews: PullRequests::PageData::ThreadPreviews::Payload.call(toolbar_data.thread_previews),
        urls: UrlsData.new(
          checks: header_data["urls"]["checks"],
          commits: header_data["urls"]["commits"],
          conversation: header_data["urls"]["conversation"],
          files: header_data["urls"]["files"],
          walkthrough: header_data["urls"]["walkthrough"]
        ),
        viewerPendingReview: PullRequests::PageData::Files::ReviewMenu::Payload.call(toolbar_data.viewer_pending_review)
      )
    end
  end
end
