# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::ThreadComments
  class Loader
    include GitHub::ResilienceMixin

    class UserContentEdit < T::Struct
      const :editor, T.nilable(User)
      const :id, T.nilable(String)
    end

    class Comment < T::Struct
      const :author_association, String
      const :author_avatar_url, T.nilable(String)
      const :body_html, String
      const :comment, PullRequestReviewComment
      const :current_diff_resource_path, T.nilable(String)
      const :last_user_content_edit, T.nilable(UserContentEdit)
      const :last_editor_avatar_url, T.nilable(String)
      const :outdated, T::Boolean
      const :published_at, T.nilable(String)
      const :reference_author_login, T.nilable(String)
      const :stafftools_url, T.nilable(String)
      const :subject_type, T.nilable(String)
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
    end

    sig { returns(T.nilable(ConditionalAccess::Web::Filter)) }
    attr_reader :cap_filter

    sig { returns(PullRequestReviewThread) }
    attr_reader :thread

    sig { returns(T.nilable(User)) }
    attr_reader :current_user

    sig { returns(T.nilable(Integer)) }
    attr_reader :max_comments

    sig do
      params(
        current_user: T.nilable(User),
        max_comments: T.nilable(Integer),
        thread: PullRequestReviewThread,
        cap_filter: T.nilable(ConditionalAccess::Web::Filter),
      ).returns(T::Array[Comment])
    end
    def self.load(current_user:, max_comments:, thread:, cap_filter: nil)
      new(cap_filter:, current_user:, max_comments:, thread:).load
    end

    sig do
      params(

        current_user: T.nilable(User),
        max_comments: T.nilable(Integer),
        thread: PullRequestReviewThread,
        cap_filter: T.nilable(ConditionalAccess::Web::Filter),
      ).returns(Promise[T::Array[Comment]])
    end
    def self.load_async(current_user:, max_comments:, thread:, cap_filter: nil)
      new(cap_filter:, current_user:, max_comments:, thread:).load_async
    end

    sig do
      params(current_user: T.nilable(User), max_comments: T.nilable(Integer), thread: PullRequestReviewThread, cap_filter: T.nilable(ConditionalAccess::Web::Filter)).void
    end
    def initialize(current_user:, max_comments:, thread:, cap_filter: nil)
      @cap_filter = cap_filter
      @current_user = current_user
      @max_comments = max_comments
      @thread = thread
    end

    sig { returns(T::Array[Comment]) }
    def load
      load_async.sync
    end

    sig { returns(Promise[T::Array[Comment]]) }
    def load_async
      review_comments = max_comments.present? ? thread.review_comments.first(T.must(max_comments)) : thread.review_comments

      comments_data = Promise.all(
        review_comments.map do |comment|
          body_html_context = {
            viewer: @current_user,
            cap_filter: @cap_filter,
            unfurl_references: true,
          }

          Promise.all([
            with_async_database_error_fallback(async_last_user_content_edit(comment), fallback: nil),
            with_async_database_error_fallback(comment.async_body_html(context: body_html_context), fallback: ""),
            with_async_database_error_fallback(comment.async_current_diff_path_uri, fallback: nil),
            with_async_database_error_fallback(T.unsafe(comment).async_outdated, fallback: false),
            with_async_database_error_fallback(comment.async_submitted_at, fallback: nil),
            with_async_database_error_fallback(T.unsafe(comment).async_subject_type, fallback: nil),
            with_async_database_error_fallback(comment.async_viewer_can_delete?(@current_user), fallback: false),
            with_async_database_error_fallback(comment.async_minimizable_by?(@current_user), fallback: false),
            with_async_database_error_fallback(async_viewer_can_see_minimize_button?(comment), fallback: false),
            with_async_database_error_fallback(async_viewer_can_see_unminimize_button?(comment), fallback: false),
            with_async_database_error_fallback(comment.async_viewer_can_report?(@current_user), fallback: false),
            with_async_database_error_fallback(comment.async_viewer_can_report_to_maintainer?(@current_user), fallback: false),
            with_async_database_error_fallback(comment.async_viewer_can_update?(@current_user), fallback: false),
            with_async_database_error_fallback(comment.async_viewer_relationship(@current_user), fallback: "none"),
          ]).then do |results|
            last_user_content_edit, body_html, current_diff_resource_path, outdated, published_at, subject_type, viewer_can_delete, viewer_can_minimize, viewer_can_see_minimize_button, viewer_can_see_unminimize_button, viewer_can_report, viewer_can_report_to_maintainer, viewer_can_update, viewer_relationship = results

            Comment.new(
              comment: comment,
              author_association:  with_database_error_fallback(fallback: "NONE") { comment.author_association_symbol.to_s.upcase },
              author_avatar_url: comment.user&.primary_avatar_url,
              body_html: body_html,
              current_diff_resource_path: current_diff_resource_path&.to_s,
              last_editor_avatar_url: last_user_content_edit&.editor&.primary_avatar_url,
              last_user_content_edit: last_user_content_edit,
              outdated: outdated,
              published_at: published_at&.to_s,
              reference_author_login: comment.pull_request&.user&.display_login,
              stafftools_url: with_database_error_fallback(fallback: nil) { stafftools_url(comment) },
              subject_type: subject_type,
              viewer_can_block_from_org: with_database_error_fallback(fallback: false) { comment.viewer_can_block_from_org?(@current_user) },
              viewer_can_delete: viewer_can_delete,
              viewer_can_minimize: viewer_can_minimize,
              viewer_can_see_minimize_button: viewer_can_see_minimize_button,
              viewer_can_see_unminimize_button: viewer_can_see_unminimize_button,
              viewer_can_report: viewer_can_report,
              viewer_can_report_to_maintainer: viewer_can_report_to_maintainer,
              viewer_can_unblock_from_org: with_database_error_fallback(fallback: false) { comment.viewer_can_unblock_from_org?(@current_user) },
              viewer_can_update: viewer_can_update,
              viewer_did_author: comment.user_id == @current_user&.id,
              viewer_relationship: viewer_relationship.to_s.upcase
            )
          end
        end
      )
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
          repo.async_pushable_by?(current_user).then do |can_push|
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
          repo.async_pushable_by?(current_user).then do |can_push|
            can_push && can_unminimize
          end
        end
      end
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
  end
end
