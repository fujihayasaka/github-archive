# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::Files
  class Payload
    include ActionView::Helpers::AssetUrlHelper

    class PullRequestData < T::Struct
      const :author, T::Hash[String, T.nilable(String)]
      const :aliveChannel, String
      const :baseBranch, String
      const :commitsCount, Integer
      const :comparison, PullRequests::PageData::Files::Toolbar::Payload::Comparison
      const :globalRelayId, String
      const :headBranch, String
      const :headRepositoryName, T.nilable(String)
      const :headRepositoryOwnerLogin, T.nilable(String)
      const :id, Integer
      const :isInAdvisoryRepo, T::Boolean
      const :mergedBy, T.nilable(String)
      const :mergedTime, T.nilable(String)
      const :number, Integer
      const :pathName, String
      const :state, String
      const :title, String
      const :titleHtml, String
      const :viewerAllowedNonCommentReviewTypes, T::Array[PullRequests::PageData::Files::Toolbar::Loader::AllowedNonCommentReviewType]
      const :viewerHasViolatedPushPolicy, T::Boolean
      const :viewerIsCopilotAttributed, T::Boolean
    end

    class Repository < T::Struct
      const :codespacesEnabled, T::Boolean
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
      const :canComment, T::Boolean
      const :currentUserAvatarUrl, T.nilable(String)
      const :currentUserLogin, T.nilable(String)
      const :canEditTitle, T::Boolean
      const :hasCopilotAccess, T::Boolean
      const :canApplySuggestion, T::Boolean
      const :isFileTreeExpanded, T::Boolean
      const :lastReviewOid, T.nilable(String)
      const :shouldShowViewedFilesCount, T::Boolean
      const :tabSize, T.nilable(Integer)
      const :viewedFilesCount, Numeric
      const :viewSettings, PullRequests::PageData::Files::Toolbar::Payload::DiffViewSettings
    end

    class UrlsData < T::Struct
      const :checks, String
      const :commits, String
      const :conversation, T.nilable(String)
      const :files, String
      const :images, T::Hash[String, String], factory: -> { {} }
      const :walkthrough, String
    end

    class CommentsData < T::Struct
      # Diff commenting components expect this to be a Relay-generated ID for appending items to a collection. Since we are not using Relay on the client any longer, we are just passing a value anyway.
      const :__id, String
      const :comments, T::Array[PullRequests::PageData::ThreadComments::Payload::PullRequestComment]
    end

    class ComparisonView < T::Enum
      enums do
        Commit = new("COMMIT")
        Full = new("FULL")
        Range = new("RANGE")
      end
    end

    class ComparisonRange < T::Struct
      const :baseOid, String
      const :headOid, String
    end

    class Comparison < T::Struct
      const :fullDiff, ComparisonRange
      const :selectedRange, T.nilable(ComparisonRange)
      const :viewing, ComparisonView
    end

    class ThreadWithComments < T::Struct
      const :id, String
      const :subjectType, String
      const :isResolved, T::Boolean
      const :resolvedBy, T.nilable(String)
      const :viewerCanReply, T::Boolean
      const :commentsData, CommentsData
      const :reviewCommentsLimit, Integer
      const :reviewCommentsLimitExceeded, T::Boolean
    end

    class FileFilterState < T::Struct
      # Counts by file extension
      const :fileExtensions, T::Hash[String, Numeric]
      const :filterText, String
      const :showDeletedFiles, T::Boolean
      const :showOnlyManifestFiles, T::Boolean
      const :showOnlyOwnedFiles, T::Boolean
      const :showVendoredFiles, T::Boolean
      const :showViewedFiles, T::Boolean
      const :unselectedFileExtensions, T::Array[String]
    end

    class FileFilterMenuOptions < T::Struct
      const :canSeeCodeownersFilter, T::Boolean
      const :canSeeDeletedFilesFilter, T::Boolean
      const :canSeeOnlyManifestFilesFilter, T::Boolean
      const :canSeeVendorFilesFilter, T::Boolean
    end

    class FileFilterData < T::Struct
      const :initialState, FileFilterState
      const :menuOptions, FileFilterMenuOptions
    end

    class PageLimits < T::Struct
      const :annotationsLimit, Integer
      const :annotationsLimitExceeded, T::Boolean
      const :filesLimit, Integer
      const :filesLimitExceeded, T::Boolean
      const :reviewCommentsPerThreadLimit, Integer
      const :reviewThreadsLimit, Integer
      const :reviewThreadsLimitExceeded, T::Boolean
    end

    class UserNotice < T::Struct
      const :name, String
      const :dismissed, T::Boolean
    end

    class Payload < T::Struct
      const :aliveChannel, String
      const :bannersData, T::Hash[String, T::Hash[String, T::Hash[String, Object]]]
      const :changeGroupGeneration, PullRequests::PageData::ChangeGroupGeneration::Payload::ChangeGroupGeneration
      const :codeowners, T.nilable(PullRequests::PageData::Codeowners::Payload::Payload)
      const :commits, T::Array[PullRequests::PageData::Files::FileTree::Payload::Commit]
      const :comparison, Comparison
      const :diffSummaries, T::Array[PullRequests::PageData::Files::FileTree::Payload::DiffSummary]
      const :diffContents, T::Array[PullRequests::PageData::Diffs::Contents::Payload::DiffEntry]
      const :fileFilter, FileFilterData
      const :pullRequest, PullRequestData
      const :repository, Repository
      const :threads, T::Hash[Numeric, ThreadWithComments]
      const :urls, UrlsData
      const :user, User
      const :userNotices, T::Array[UserNotice]
      const :viewerPendingReview, T.nilable(PullRequests::PageData::Files::ReviewMenu::Payload::PendingReview)
      const :markers, T.untyped # rubocop:disable Sorbet/ForbidUntypedStructProps Temporary
      const :pageLimits, PageLimits
      const :isSingleFileMode, T::Boolean, default: false
      const :commit, T.nilable(PullRequests::PageData::Commit::Payload::Payload)
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
      codeowners_data = loader_data.codeowners
      comparison_data = loader_data.comparison
      diff_contents_data = loader_data.diff_contents
      file_filter_data = loader_data.file_filter
      file_tree_data = loader_data.file_tree
      header_data = loader_data.header
      toolbar_data = loader_data.toolbar
      user_data = loader_data.user
      change_group_generation = loader_data.change_group_generation
      enable_diff_consolidation = loader_data.enable_diff_consolidation
      commit_data = loader_data.commit

      codeowners_payload = \
        unless codeowners_data.nil?
          PullRequests::PageData::Codeowners::Payload.call(codeowners_data)
        end

      commit_payload = \
        unless commit_data.nil?
          PullRequests::PageData::Commit::Payload.call(commit_data)
        end

      diff_contents_payload = PullRequests::PageData::Diffs::Contents::Payload.new
      diff_contents = diff_contents_payload.call(diff_contents_data)

      threads = T.let({}, T::Hash[Numeric, ThreadWithComments])
      loader_data.threads.each_with_object(threads) do |thread_data|
        threads[thread_data.id] = ThreadWithComments.new(
          id: thread_data.id.to_s,
          subjectType: thread_data.subject_type.upcase,
          isResolved: thread_data.is_resolved,
          resolvedBy: thread_data.resolved_by&.display_login,
          viewerCanReply: thread_data.viewer_can_reply,
          commentsData: CommentsData.new({
            comments: PullRequests::PageData::ThreadComments::Payload.call(thread_data.thread_comments),
            __id: thread_data.id.to_s,
          }),
          reviewCommentsLimit: thread_data.review_comments_limit,
          reviewCommentsLimitExceeded: thread_data.review_comments_limit_exceeded,
        )
      end

      filter_options = {
        can_see_codeowners_filter: T.let(false, T::Boolean),
        can_see_deleted_files_filter: T.let(false, T::Boolean),
        can_see_only_manifest_files_filter: T.let(false, T::Boolean),
        can_see_vendor_files_filter: T.let(false, T::Boolean),
      }

      # Will be used to determine can_see_codeowners_filter
      viewer_has_owned_files = T.let(false, T::Boolean)
      viewer_has_unowned_files = T.let(false, T::Boolean)

      file_tree_payload = PullRequests::PageData::Files::FileTree::Payload.new

      # First, create all diff summaries without merging
      diff_summaries = file_tree_data.diffs.map do |diff_summary|
        path = diff_summary.path
        is_removed = diff_summary.is_removed?
        is_codeowner = diff_summary.is_codeowner
        is_manifest_file = diff_summary.is_manifest_file
        is_vendored = diff_summary.vendored?

        viewer_has_owned_files ||= !!is_codeowner
        viewer_has_unowned_files ||= !is_codeowner
        filter_options[:can_see_deleted_files_filter] ||= is_removed
        filter_options[:can_see_only_manifest_files_filter] ||= is_manifest_file
        filter_options[:can_see_vendor_files_filter] ||= is_vendored

        PullRequests::PageData::Files::FileTree::Payload::DiffSummary.new(
          changeType: diff_summary.change_type,
          isCodeowner: is_codeowner,
          isManifestFile: is_manifest_file,
          isVendored: is_vendored,
          linesAdded: diff_summary.lines_added,
          linesChanged: diff_summary.lines_changed,
          linesDeleted: diff_summary.lines_deleted,
          markedAsViewed: file_tree_data.viewed_files.reviewed?(path),
          path: path,
          pathDigest: Digest::SHA256.hexdigest(path),
          highestAnnotationLevel: file_tree_payload.highest_annotation_level(diff_summary.annotations),
          markersMap: file_tree_payload.markers_map(
            threads: diff_summary.threads,
            annotations: diff_summary.annotations,
          ),
          isSymlink: diff_summary.is_symlink,
        )
      end

      # Check if there are any duplicate paths
      paths = diff_summaries.map(&:path)
      has_duplicates = paths.length != paths.uniq.length

      GitHub.dogstats.increment("pull_request.duplicate_entries.files", tags: ["has_duplicates:#{has_duplicates}"])


      # Only merge if duplicates exist
      diff_summaries = merge_duplicate_diff_summaries(diff_summaries) if has_duplicates && enable_diff_consolidation

      # The codeowners filter should only be visible if the user owns at least 1, but not all files in the PR.
      if viewer_has_owned_files && viewer_has_unowned_files
        filter_options[:can_see_codeowners_filter] = true
      end

      Payload.new(
        aliveChannel: header_data["aliveChannel"],
        bannersData: header_data["bannersData"],
        changeGroupGeneration: PullRequests::PageData::ChangeGroupGeneration::Payload.call(change_group_generation),
        codeowners: codeowners_payload,
        commits: file_tree_data.commits.map do |commit|
          PullRequests::PageData::Files::FileTree::Payload::Commit.new(
            actorLogin: commit.user_display_login,
            createdAt: commit.created_at.iso8601,
            messageHeadline: commit.short_message_text,
            oid: commit.oid,
            shortOid: commit.abbreviated_oid
          )
        end,
        comparison: derive_comparison(comparison_data, commit_payload),
        diffSummaries: diff_summaries,
        diffContents: diff_contents,
        fileFilter: FileFilterData.new(
          initialState: FileFilterState.new(
            fileExtensions: file_filter_data.file_extensions_with_counts,
            # We don't do text-based filtering on the server (yet), but `filterText` is required by the client,
            # so we're including a hard-coded value here.
            filterText: "",
            showDeletedFiles: file_filter_data.show_deleted_files,
            showOnlyManifestFiles: file_filter_data.show_only_manifest_files,
            showOnlyOwnedFiles: file_filter_data.show_only_owned_files,
            showVendoredFiles: file_filter_data.show_vendored_files,
            showViewedFiles: file_filter_data.show_viewed_files,
            unselectedFileExtensions: file_filter_data.unselected_file_extensions,
          ),
          menuOptions: FileFilterMenuOptions.new(
            canSeeCodeownersFilter: filter_options[:can_see_codeowners_filter],
            canSeeDeletedFilesFilter: filter_options[:can_see_deleted_files_filter],
            canSeeOnlyManifestFilesFilter: filter_options[:can_see_only_manifest_files_filter],
            canSeeVendorFilesFilter: filter_options[:can_see_vendor_files_filter],
          )
        ),
        pullRequest: PullRequestData.new(
          author: header_data["pullRequest"]["author"],
          aliveChannel: toolbar_data.pull_request.alive_channel,
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
          id: header_data["pullRequest"]["id"],
          isInAdvisoryRepo: header_data["pullRequest"]["isInAdvisoryRepo"],
          mergedBy: header_data["pullRequest"]["mergedBy"],
          mergedTime: header_data["pullRequest"]["mergedTime"],
          number: header_data["pullRequest"]["number"],
          pathName: toolbar_data.pull_request.path_name,
          state: header_data["pullRequest"]["state"],
          title: header_data["pullRequest"]["title"],
          titleHtml: header_data["pullRequest"]["titleHtml"],
          viewerAllowedNonCommentReviewTypes: toolbar_data.pull_request.viewer_allowed_non_comment_review_types,
          viewerHasViolatedPushPolicy: toolbar_data.pull_request.viewer_has_violated_push_policy,
          viewerIsCopilotAttributed: toolbar_data.pull_request.viewer_is_copilot_attributed,
        ),
        repository: Repository.new(
          codespacesEnabled: header_data["repository"]["codespacesEnabled"],
          editorEnabled: header_data["repository"]["editorEnabled"],
          defaultBranch: header_data["repository"]["defaultBranch"],
          id: header_data["repository"]["id"],
          isEnterprise: header_data["repository"]["isEnterprise"],
          name: header_data["repository"]["name"],
          ownerLogin: header_data["repository"]["ownerLogin"],
          viewerPermission: toolbar_data.pull_request.viewer_permission
        ),
        threads: threads,
        user: User.new(
          canChangeBase: header_data["user"]["canChangeBase"],
          canComment: user_data.can_comment,
          currentUserAvatarUrl: toolbar_data.current_user&.primary_avatar_url,
          currentUserLogin: toolbar_data.current_user&.display_login,
          canEditTitle: header_data["user"]["canEditTitle"],
          hasCopilotAccess: toolbar_data.copilot_access_allowed,
          canApplySuggestion: toolbar_data.pull_request.viewer_can_apply_suggestion,
          isFileTreeExpanded: toolbar_data.is_file_tree_expanded,
          lastReviewOid: file_tree_data.last_review_oid,
          shouldShowViewedFilesCount: toolbar_data.should_show_viewed_files_count,
          tabSize: user_data.tab_size,
          viewedFilesCount: toolbar_data.viewed_files_count,
          viewSettings: PullRequests::PageData::Files::Toolbar::Payload::DiffViewSettings.new(
            hideWhitespace: toolbar_data.view_settings.hide_whitespace,
            lineSpacing: toolbar_data.view_settings.line_spacing,
            showChangeGroups: toolbar_data.view_settings.show_change_groups,
            splitPreference: PullRequests::PageData::Files::Toolbar::Payload::SplitPreference.deserialize(toolbar_data.view_settings.split_preference.serialize),
            commentsPreference: PullRequests::PageData::Files::Toolbar::Payload::CommentsPreference.deserialize(toolbar_data.view_settings.comments_preference.serialize),
          )
        ),
        userNotices: user_data.notices.map do |notice|
          UserNotice.new(
            name: notice.name,
            dismissed: notice.dismissed,
          )
        end,
        urls: UrlsData.new(
          checks: header_data["urls"]["checks"],
          commits: header_data["urls"]["commits"],
          conversation: header_data["urls"]["conversation"],
          files: header_data["urls"]["files"],
          images: { "mona-hifive" => image_url("/images/mona-hifive.gif") },
          walkthrough: header_data["urls"]["walkthrough"],
        ),
        viewerPendingReview: PullRequests::PageData::Files::ReviewMenu::Payload.call(toolbar_data.viewer_pending_review),
        markers: {
          threads: threads,
          annotations: PullRequests::PageData::Annotations::Payload.call(toolbar_data.annotations).index_by(&:databaseId),
        },
        pageLimits: PageLimits.new(
                      annotationsLimit: loader_data.limit_config.annotations_limit,
                      annotationsLimitExceeded: loader_data.limit_config.annotations_limit_exceeded?,
                      filesLimit: loader_data.limit_config.files_limit,
                      filesLimitExceeded: loader_data.limit_config.files_limit_exceeded?,
                      reviewCommentsPerThreadLimit: loader_data.limit_config.review_comments_per_thread_limit,
                      reviewThreadsLimit: loader_data.limit_config.review_threads_limit,
                      reviewThreadsLimitExceeded: loader_data.limit_config.review_threads_limit_exceeded?,
                    ),
       isSingleFileMode: loader_data.single_file_mode || false,
       commit: commit_payload,
      )
    end

    private

    sig { params(diff_summaries: T::Array[PullRequests::PageData::Files::FileTree::Payload::DiffSummary]).returns(T::Array[PullRequests::PageData::Files::FileTree::Payload::DiffSummary]) }
    def merge_duplicate_diff_summaries(diff_summaries)
      summaries_map = T.let({}, T::Hash[String, PullRequests::PageData::Files::FileTree::Payload::DiffSummary])

      diff_summaries.each do |summary|
        existing = summaries_map[summary.path]

        if existing
          summaries_map[summary.path] = merge_diff_summaries(existing, summary)
        else
          summaries_map[summary.path] = summary
        end
      end

      summaries_map.values
    end

    sig { params(existing: PullRequests::PageData::Files::FileTree::Payload::DiffSummary, current: PullRequests::PageData::Files::FileTree::Payload::DiffSummary).returns(PullRequests::PageData::Files::FileTree::Payload::DiffSummary) }
    def merge_diff_summaries(existing, current)
      merged_change_type = calculate_merged_change_type_for_diff_summary(existing.changeType, current.changeType)

      PullRequests::PageData::Files::FileTree::Payload::DiffSummary.new(
        changeType: merged_change_type,
        isCodeowner: current.isCodeowner,
        isManifestFile: current.isManifestFile,
        isVendored: current.isVendored,
        linesAdded: existing.linesAdded + current.linesAdded,
        linesChanged: existing.linesChanged + current.linesChanged,
        linesDeleted: existing.linesDeleted + current.linesDeleted,
        markedAsViewed: current.markedAsViewed,
        path: existing.path,
        pathDigest: existing.pathDigest,
        highestAnnotationLevel: current.highestAnnotationLevel,
        markersMap: current.markersMap,
        isSymlink: existing.isSymlink || current.isSymlink,
      )
    end

    sig { params(type1: Diffs::Entry::ChangeType, type2: Diffs::Entry::ChangeType).returns(Diffs::Entry::ChangeType) }
    def calculate_merged_change_type_for_diff_summary(type1, type2)
      if (type1 == Diffs::Entry::ChangeType::Removed && type2 == Diffs::Entry::ChangeType::Added) ||
         (type1 == Diffs::Entry::ChangeType::Added && type2 == Diffs::Entry::ChangeType::Removed)
        Diffs::Entry::ChangeType::Changed
      else
        type2
      end
    end

    sig do
      params(
        comparison_data: PullRequests::PageData::Files::Loader::ComparisonData,
        commit_payload: T.nilable(PullRequests::PageData::Commit::Payload::Payload),
      ).returns(Comparison)
    end
    def derive_comparison(comparison_data, commit_payload)
      historical_comparison = comparison_data.historical_comparison
      current_comparison = comparison_data.current_comparison

      # Only send selectedRange when viewing a range (not the full diff)
      # This mimics the old client behavior where selectedRange was only
      # populated when a range was parsed from the URL
      #
      # When the current base OID equals the merge base, we use the historical comparison base OID instead.
      # This is the equivalent of `/changes/BASE..oid` or `/files/oid` ranges.
      selected_range =
        if comparison_data.is_current
          nil
        else
          base_is_merge_base = current_comparison.base_oid == comparison_data.merge_base_oid
          ComparisonRange.new(
            baseOid: base_is_merge_base ? historical_comparison.base_oid : current_comparison.base_oid,
            headOid: current_comparison.head_oid,
          )
        end

      viewing =
        if commit_payload.present?
          ComparisonView::Commit
        elsif selected_range.present?
          ComparisonView::Range
        else
          ComparisonView::Full
        end

      Comparison.new(
         fullDiff: ComparisonRange.new(
           baseOid: historical_comparison.base_oid,
           headOid: historical_comparison.head_oid,
         ),
         selectedRange: selected_range,
         viewing: viewing
        )
    end
  end
end
