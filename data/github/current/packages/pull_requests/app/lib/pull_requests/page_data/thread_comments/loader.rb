# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::ThreadComments
  class Loader
    include GitHub::ResilienceMixin

    class CommentDataType < T::Enum
      enums do
        Default = new # load all of the data in the comment
        Preview = new # loads the data of the comment but without info for the header actions and the latest user content edit
      end
    end

    class CommentReviewVariantType < T::Enum
      enums do
        Vanilla = new
        CodeScanning = new("code_scanning")
        Copilot = new
        Dependabot = new
        CodeQuality = new("code_quality")
        Automated = new("automated")
      end
    end

    class UserContentEdit < T::Struct
      const :editor, T.nilable(User)
      const :id, T.nilable(String)
    end

    class Comment < T::Struct
      const :author_association, String
      const :author_avatar_url, T.nilable(String)
      const :automated_comment, T.nilable(AutomatedReviewComment), default: nil
      const :body_html, String
      const :body_version, String
      const :comment, PullRequestReviewComment
      const :current_diff_resource_path, T.nilable(String)
      const :last_user_content_edit, T.nilable(UserContentEdit)
      const :last_editor_avatar_url, T.nilable(String)
      const :published_at, T.nilable(String)
      const :reference_author_login, T.nilable(String)
      const :reaction_groups, T::Array[PullRequests::PageData::Helpers::Reactable::Loader::ReactionGroup]
      const :stafftools_url, T.nilable(String)
      const :subject_type, T.nilable(String)
      const :url, String
      const :viewer_can_block_from_org, T::Boolean
      const :viewer_can_delete, T::Boolean
      const :viewer_can_minimize, T::Boolean
      const :viewer_can_see_minimize_button, T::Boolean
      const :viewer_can_see_unminimize_button, T::Boolean
      const :viewer_can_report, T::Boolean
      const :viewer_can_report_to_maintainer, T::Boolean
      const :viewer_can_unblock_from_org, T::Boolean
      const :viewer_can_update, T::Boolean
      const :viewer_did_author, T::Boolean
      const :viewer_relationship, String
      const :viewer_can_react, T::Boolean
      const :viewer_can_dismiss_automated_comment, T::Boolean
      const :viewer_can_reopen_automated_comment, T::Boolean
      const :review_variant_type, T.nilable(CommentReviewVariantType)
    end

    sig { returns(T.nilable(ConditionalAccess::Web::Filter)) }
    attr_reader :cap_filter

    sig { returns(T.nilable(User)) }
    attr_reader :current_user

    sig { returns(T.nilable(CommentDataType)) }
    attr_reader :comment_data_type

    sig { returns(T.nilable(Integer)) }
    attr_reader :max_comments

    sig do
      params(
        current_user: T.nilable(User),
        max_comments: T.nilable(Integer),
        threads: T::Enumerable[PullRequestReviewThread],
        cap_filter: T.nilable(ConditionalAccess::Web::Filter),
        comment_data_type: T.nilable(CommentDataType),
      ).returns(T::Hash[Integer, T::Array[PullRequests::PageData::ThreadComments::Loader::Comment]])
    end
    def self.load(current_user:, max_comments:, threads:, cap_filter: nil, comment_data_type: CommentDataType::Default)
      new(cap_filter:, current_user:, comment_data_type:, max_comments:, threads:).load
    end

    sig do
      params(
        current_user: T.nilable(User),
        max_comments: T.nilable(Integer),
        threads: T::Enumerable[PullRequestReviewThread],
        cap_filter: T.nilable(ConditionalAccess::Web::Filter),
        comment_data_type: T.nilable(CommentDataType),
      ).void
    end
    def initialize(current_user:, max_comments:, threads:, cap_filter: nil, comment_data_type: CommentDataType::Default)
      @cap_filter = cap_filter
      @current_user = current_user
      @comment_data_type = comment_data_type
      @max_comments = max_comments
      @threads = threads
    end

    sig { returns(T::Hash[Integer, T::Array[PullRequests::PageData::ThreadComments::Loader::Comment]]) }
    def load
      thread_ids = @threads&.map(&:id) || []
      max_comments_across_threads = max_comments.present? ? T.must(max_comments) * thread_ids.size : nil
      associations = [
        :pull_request_review,
        :user,
        :automated_review_comment,
        { latest_user_content_edit: :editor },
        { pull_request: :issue },
        { pull_request: :repository },
        { pull_request: :user },
        { reactions: :user },
        { repository: :owner },
      ]

      review_comments = if max_comments_across_threads.present?
        PullRequestReviewComment.where(pull_request_review_thread_id: thread_ids).preload(associations).with_submitted_state.limit(max_comments_across_threads)
      else
        PullRequestReviewComment.where(pull_request_review_thread_id: thread_ids).preload(associations).with_submitted_state
      end
      pending_comments = PullRequestReviewComment.where(pull_request_review_thread_id: thread_ids, user: @current_user).pending
      review_comments += pending_comments # domain-isolation-query-violation:ignore:packages/issues (SELECT)

      GitHub::PrefillAssociations.prefill_associations(review_comments, :pull_request_review_thread, available_records: @threads)

      body_html_context = {
        viewer: @current_user,
        cap_filter: @cap_filter,
        unfurl_references: true,
      }

      is_preview = @comment_data_type == CommentDataType::Preview

      GitHub::PrefillAssociations.prefill_batch_method(review_comments, :prelude_body_html, context: body_html_context)
      viewer_can_react_by_comment = batch_viewer_can_react(review_comments)

      unless is_preview
        minimize_button_permissions_by_comment = batch_minimize_button_permissions(review_comments)
        viewer_can_update_by_comment = batch_viewer_can_update(review_comments)
        viewer_permissions_by_comment = batch_viewer_permissions(review_comments)
      end

      automated_comments_by_comment = batch_automated_comment(review_comments)

      comments_data = Promise.all(
        review_comments.map do |comment|
          # Create a hash to make the data more accessible after the promises have resolved
          comment_data = {
            author_association: with_async_database_error_fallback(comment.author_association.async_to_sym, fallback: :none),
            # Note(@aliceclv): once we have automated comments stored in the DB, we can do:
            # automated_comment: with_async_database_error_fallback(comment.async_automated_review_comment, fallback: nil)
            last_user_content_edit: !is_preview ? with_async_database_error_fallback(async_last_user_content_edit(comment), fallback: nil) : Promise.resolve(nil),
            body_html: Promise.resolve(comment.body_html(context: body_html_context)),
            current_diff_resource_path: with_async_database_error_fallback(comment.async_current_diff_path_uri, fallback: nil),
            published_at: with_async_database_error_fallback(comment.async_submitted_at, fallback: nil),
            subject_type: with_async_database_error_fallback(T.unsafe(comment).async_subject_type, fallback: nil),
            viewer_can_block_from_org: !is_preview ? Promise.resolve(viewer_permissions_by_comment.dig(comment, :can_block_from_org) || false) : Promise.resolve(false),
            viewer_can_unblock_from_org: !is_preview ? Promise.resolve(viewer_permissions_by_comment.dig(comment, :can_unblock_from_org) || false) : Promise.resolve(false),
            viewer_can_delete: !is_preview ? Promise.resolve(viewer_permissions_by_comment.dig(comment, :can_delete) || false) : Promise.resolve(false),
            viewer_can_minimize: !is_preview ? with_async_database_error_fallback(comment.async_minimizable_by?(@current_user), fallback: false) : Promise.resolve(false),
            viewer_can_see_minimize_button: !is_preview ? Promise.resolve(minimize_button_permissions_by_comment.dig(comment, :can_see_minimize_button) || false) : Promise.resolve(false),
            viewer_can_see_unminimize_button: !is_preview ? Promise.resolve(minimize_button_permissions_by_comment.dig(comment, :can_see_unminimize_button) || false) : Promise.resolve(false),
            viewer_can_report: !is_preview ? Promise.resolve(viewer_permissions_by_comment.dig(comment, :can_report) || false) : Promise.resolve(false),
            viewer_can_report_to_maintainer: !is_preview ? Promise.resolve(viewer_permissions_by_comment.dig(comment, :can_report_to_maintainer) || false) : Promise.resolve(false),
            viewer_can_update: !is_preview ? Promise.resolve(viewer_can_update_by_comment[comment] || false) : Promise.resolve(false),
            viewer_relationship: with_async_database_error_fallback(comment.async_viewer_relationship(@current_user), fallback: "none"),
            viewer_can_react: Promise.resolve(viewer_can_react_by_comment[comment] || false),
            reaction_groups: with_async_database_error_fallback(PullRequests::PageData::Helpers::Reactable::Loader.async_reaction_groups(comment, @current_user), fallback: [])
          }
          Promise.all(comment_data.values).then do
            # Check if we have an automated review comment
            review_variant_type = CommentReviewVariantType.try_deserialize(comment.pull_request_review&.variant_type)
            is_automated_comment = review_variant_type == CommentReviewVariantType::Automated
            automated_comment = is_automated_comment ? automated_comments_by_comment[comment] : nil

            # Calling sync on the values below no-ops because the data is already loaded and resolved
            Comment.new(
              comment: comment,
              # TODO(@aliceclv): figure out if we need automated comment when comment is in preview
              automated_comment: automated_comment,
              author_association:  comment_data[:author_association].sync.to_s.upcase,
              author_avatar_url: comment.user&.primary_avatar_url,
              body_html: comment_data[:body_html].sync,
              body_version: comment.body_version,
              current_diff_resource_path: comment_data[:current_diff_resource_path].sync&.to_s,
              last_editor_avatar_url: comment_data[:last_user_content_edit].sync&.editor&.primary_avatar_url,
              last_user_content_edit: comment_data[:last_user_content_edit].sync,
              published_at: comment_data[:published_at].sync&.iso8601,
              reference_author_login: comment.pull_request&.user&.display_login,
              stafftools_url: !is_preview ? with_database_error_fallback(fallback: nil) { stafftools_url(comment) } : nil,
              subject_type: comment_data[:subject_type].sync,
              url: comment.url,
              viewer_can_block_from_org: comment_data[:viewer_can_block_from_org].sync,
              viewer_can_delete: comment_data[:viewer_can_delete].sync,
              viewer_can_minimize: comment_data[:viewer_can_minimize].sync,
              viewer_can_see_minimize_button: comment_data[:viewer_can_see_minimize_button].sync,
              viewer_can_see_unminimize_button: comment_data[:viewer_can_see_unminimize_button].sync,
              viewer_can_report: comment_data[:viewer_can_report].sync,
              viewer_can_report_to_maintainer: comment_data[:viewer_can_report_to_maintainer].sync,
              viewer_can_unblock_from_org: comment_data[:viewer_can_unblock_from_org].sync,
              viewer_can_update: comment_data[:viewer_can_update].sync,
              viewer_did_author: comment.user_id == @current_user&.id,
              viewer_relationship: comment_data[:viewer_relationship].sync.to_s.upcase,
              viewer_can_react: comment_data[:viewer_can_react].sync,
              viewer_can_dismiss_automated_comment: (@current_user && automated_comment && automated_comment.can_dismiss?(user: @current_user)) || false,
              viewer_can_reopen_automated_comment: (@current_user && automated_comment && automated_comment.can_reopen?(user: @current_user)) || false,
              reaction_groups: comment_data[:reaction_groups].sync,
              review_variant_type: review_variant_type,
            )
          end
        end
      ).sync

      comments_data.group_by { |comment| comment.comment.pull_request_review_thread_id }
    end

    private

    sig { params(comment: PullRequestReviewComment).returns(Promise[T::Boolean]) }
    def async_viewer_can_see_minimize_button?(comment)
      comment.async_minimizable_by?(current_user).then do |can_minimize|
        # Return false if object is not part of a repo
        next false unless comment.respond_to?(:repository)

        # Return result if actor isn't a site admin
        next can_minimize unless current_user.try(:site_admin?)

        # If the user is a site admin, only show them the minimize button if they can push to the repo
        comment.async_repository.then do |repo|
          T.must(repo).async_pushable_by?(current_user).then do |can_push|
            can_push && can_minimize
          end
        end
      end
    end

    sig { params(comment: PullRequestReviewComment).returns(Promise[T::Boolean]) }
    def async_viewer_can_see_unminimize_button?(comment)
      comment.async_unminimizable_by?(current_user).then do |can_unminimize|
        # Return false if object is not part of a repo
        next false unless comment.respond_to?(:repository)

        # Return result if actor isn't a site admin
        next can_unminimize unless current_user.try(:site_admin?)

        # If the user is a site admin, only show them the minimize button if they can push to the repo
        comment.async_repository.then do |repo|
          T.must(repo).async_pushable_by?(current_user).then do |can_push|
            can_push && can_unminimize
          end
        end
      end
    end

    sig { params(comment: PullRequestReviewComment).returns(Promise[T::Boolean]) }
    def async_automated_comment_enabled?(comment)
      comment.async_repository.then do |repository|
        repository && CodeQuality.automated_review_comment_enabled?(repository)
      end
    end

    sig { params(comments: T::Array[PullRequestReviewComment]).returns(T::Hash[PullRequestReviewComment, T::Hash[Symbol, T::Boolean]]) }
    def batch_minimize_button_permissions(comments)
      result = {}
      return result unless @current_user && comments.any?

      minimize_button_promises = comments.map { |comment| async_viewer_can_see_minimize_button?(comment) }
      unminimize_button_promises = comments.map { |comment| async_viewer_can_see_unminimize_button?(comment) }

      minimize_button_results = Promise.all(minimize_button_promises).sync
      unminimize_button_results = Promise.all(unminimize_button_promises).sync

      comments.each_with_index do |comment, index|
        result[comment] = {
          can_see_minimize_button: minimize_button_results[index],
          can_see_unminimize_button: unminimize_button_results[index]
        }
      end

      result
    end

    sig { params(comment: PullRequestReviewComment).returns(Promise[T.nilable(UserContentEdit)]) }
    def async_last_user_content_edit(comment)
      comment.async_viewer_can_read_user_content_edits?(@current_user).then do |can_read|
        next unless can_read

        last_edit = comment.latest_user_content_edit

        next unless last_edit

        UserContentEdit.new(
          editor: last_edit.editor,
          id: last_edit.id&.to_s
        )
      end
    end

    sig { params(comment: PullRequestReviewComment).returns(T.nilable(String)) }
    def stafftools_url(comment)
      return nil unless @current_user.try(:site_admin?)
      return nil unless comment.respond_to?(:async_repository)

      pull_request = comment.pull_request
      return nil unless pull_request && pull_request.repository

      "/stafftools/repositories/#{T.must(pull_request.repository).name}/pull_requests/#{pull_request.number}/review_comments/#{comment.id}"
    end

    sig { params(comments: T::Array[PullRequestReviewComment]).returns(T::Hash[PullRequestReviewComment, T::Boolean]) }
    def batch_viewer_can_react(comments)
      result = {}
      return result unless @current_user && comments.any?

      promises = comments.map { |comment| comment.async_viewer_can_react?(@current_user) }
      results = Promise.all(promises).sync # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      comments.zip(results).each { |comment, can_react| result[comment] = can_react }
      result
    end

    sig { params(comments: T::Array[PullRequestReviewComment]).returns(T::Hash[PullRequestReviewComment, T::Boolean]) }
    def batch_viewer_can_update(comments)
      result = {}
      return result unless @current_user && comments.any?

      promises = comments.map { |comment| comment.async_viewer_can_update?(@current_user) }
      results = Promise.all(promises).sync
      comments.zip(results).each { |comment, can_update| result[comment] = can_update }
      result
    end

    # Batch multiple viewer permission calls for better performance
    sig { params(comments: T::Array[PullRequestReviewComment]).returns(T::Hash[PullRequestReviewComment, T::Hash[Symbol, T::Boolean]]) }
    def batch_viewer_permissions(comments)
      result = {}
      return result unless @current_user && comments.any?

      # Batch all the permission checks
      delete_promises = comments.map { |comment| comment.async_viewer_can_delete?(@current_user) }
      report_promises = comments.map { |comment| comment.async_viewer_can_report?(@current_user) }
      report_to_maintainer_promises = comments.map { |comment| comment.async_viewer_can_report_to_maintainer?(@current_user) }
      block_from_org_promises = comments.map { |comment| comment.async_viewer_can_block_from_org?(@current_user) }
      unblock_from_org_promises = comments.map { |comment| comment.async_viewer_can_unblock_from_org?(@current_user) }

      # Resolve all promises
      delete_results = Promise.all(delete_promises).sync
      report_results = Promise.all(report_promises).sync
      report_to_maintainer_results = Promise.all(report_to_maintainer_promises).sync
      block_from_org_results = Promise.all(block_from_org_promises).sync
      unblock_from_org_results = Promise.all(unblock_from_org_promises).sync

      comments.each_with_index do |comment, index|
        result[comment] = {
          can_delete: delete_results[index],
          can_report: report_results[index],
          can_report_to_maintainer: report_to_maintainer_results[index],
          can_block_from_org: block_from_org_results[index],
          can_unblock_from_org: unblock_from_org_results[index]
        }
      end

      result
    end

    # Note(@aliceclv): Once we remove the FF we can get rid of the whole method as AutomatedReviewComments are preloaded
    sig { params(comments: T::Array[PullRequestReviewComment]).returns(T::Hash[PullRequestReviewComment, AutomatedReviewComment]) }
    def batch_automated_comment(comments)
      result = {}
      return result unless @current_user && comments.any?

      # Batch automated comment feature flag checks
      automated_comment_feature_enabled_promises = comments.map { |comment| async_automated_comment_enabled?(comment) }

      # Resolve all promises
      automated_comment_feature_enabled_results = Promise.all(automated_comment_feature_enabled_promises).sync

      comments.each_with_index do |comment, index|
        feature_enabled = automated_comment_feature_enabled_results[index]
        next unless feature_enabled

        result[comment] = comment.automated_review_comment
      end
      result
    end
  end
end
