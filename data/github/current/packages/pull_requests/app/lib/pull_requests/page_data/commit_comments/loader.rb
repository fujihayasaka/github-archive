# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::CommitComments
  class Loader
    include GitHub::ResilienceMixin
    include Diff

    class UserContentEdit < T::Struct
      const :editor, T.nilable(User)
      const :id, T.nilable(String)
    end

    class Author < T::Struct
      const :id, Numeric
      const :display_login, String
      const :avatar_url, String
    end

    class Comment < T::Struct
      const :author, T.nilable(Author)
      const :author_association, Symbol
      const :body, String
      const :body_version, String
      const :created_at, ActiveSupport::TimeWithZone
      const :html_body, String
      const :id, Numeric
      const :is_hidden, T::Boolean
      const :minimized_reason, T.nilable(String)
      const :path, String
      const :position, Numeric
      const :relay_id, String
      const :thread_id, String
      const :updated_at, ActiveSupport::TimeWithZone
      const :url_fragment, String
      const :viewer_can_block_from_org, T::Boolean
      const :viewer_can_delete, T::Boolean
      const :viewer_can_minimize, T::Boolean
      const :viewer_can_read_user_content_edits, T::Boolean
      const :viewer_can_report, T::Boolean
      const :last_user_content_edit, T.nilable(UserContentEdit)
      const :viewer_can_report_to_maintainer, T::Boolean
      const :viewer_can_unblock_from_org, T::Boolean
      const :viewer_can_update, T::Boolean
      const :viewer_did_author, T::Boolean
    end

    sig { returns(T.nilable(ConditionalAccess::Web::Filter)) }
    attr_reader :cap_filter

    sig { returns(T.nilable(FileListView)) }
    attr_reader :file_list_view

    sig { returns(T.nilable(User)) }
    attr_reader :current_user

    sig { returns(T.nilable(Repository)) }
    attr_reader :current_repository

    sig do
      params(
        current_user: T.nilable(User),
        file_list_view: T.nilable(FileListView),
        current_repository: T.nilable(Repository),
        cap_filter: T.nilable(ConditionalAccess::Web::Filter),
      ).returns(T::Array[Comment])
    end
    def self.load(current_user:, file_list_view:, current_repository:, cap_filter: nil)
      new(cap_filter:, current_user:, current_repository:, file_list_view:).load
    end

    sig do
      params(
        current_user: T.nilable(User),
        file_list_view: T.nilable(FileListView),
        current_repository: T.nilable(Repository),
        cap_filter: T.nilable(ConditionalAccess::Web::Filter),
      ).returns(Promise[T::Array[Comment]])
    end
    def self.load_async(current_user:, file_list_view:, current_repository:, cap_filter: nil)
      new(cap_filter:, current_user:, current_repository:, file_list_view:).load_async
    end

    sig do
      params(current_user: T.nilable(User), file_list_view: T.nilable(FileListView), current_repository: T.nilable(Repository), cap_filter: T.nilable(ConditionalAccess::Web::Filter)).void
    end
    def initialize(current_user:, file_list_view:, current_repository:, cap_filter: nil)
      @cap_filter = cap_filter
      @current_user = current_user
      @current_repository = current_repository
      @file_list_view = file_list_view
    end

    sig { returns(T::Array[Comment]) }
    def load
      load_async.sync
    end

    sig { returns(Promise[T::Array[Comment]]) }
    def load_async
      diff_comments = @file_list_view&.threads&.flat_map(&:comments) || []

      GitHub::PrefillAssociations.prefill_associations(diff_comments, [:user, :repository], available_records: [@current_user, @current_repository])

      comments_data = Promise.all(
        diff_comments.map do |comment|
          Promise.all([
            with_async_database_error_fallback(async_last_user_content_edit(comment), fallback: nil),
            with_async_database_error_fallback(comment.async_viewer_can_read_user_content_edits?(@current_user), fallback: false),
            with_async_database_error_fallback(comment.async_minimizable_by?(@current_user), fallback: false),
            with_async_database_error_fallback(comment.async_viewer_can_report?(@current_user), fallback: false),
            with_async_database_error_fallback(comment.async_viewer_can_report_to_maintainer?(@current_user), fallback: false),
            with_async_database_error_fallback(comment.async_viewer_can_block_from_org?(@current_user), fallback: false),
            with_async_database_error_fallback(comment.async_viewer_can_unblock_from_org?(@current_user), fallback: false),
            with_async_database_error_fallback(comment.async_minimizable_by?(@current_user), fallback: false),
          ]).then do |results|
            last_user_content_edit, viewer_can_read_edits, minimizable_by, viewer_can_report, viewer_can_report_to_maintainer, viewer_can_block_from_org, viewer_can_unblock_from_org, viewer_can_minimize = results

            Comment.new(
              id: comment.id,
              relay_id: comment.global_relay_id,
              body: comment.body,
              body_version: comment.body_version,
              html_body: comment.body_html(context: { viewer: @current_user, cap_filter: cap_filter, unfurl_references: true }),
              created_at: comment.created_at,
              updated_at: comment.updated_at,
              last_user_content_edit: last_user_content_edit,
              path: comment.path,
              position: comment.position,
              is_hidden: comment.minimized?,
              viewer_can_minimize:  viewer_can_minimize,
              minimized_reason: comment.minimized_reason,
              viewer_can_delete: comment.async_viewer_can_delete?(@current_user).sync,
              viewer_can_update: comment.async_viewer_can_update?(@current_user).sync,
              viewer_can_report: comment.async_viewer_can_report?(@current_user).sync,
              viewer_can_report_to_maintainer: comment.async_viewer_can_report_to_maintainer?(@current_user).sync,
              viewer_can_block_from_org: comment.viewer_can_block_from_org?(@current_user),
              viewer_can_unblock_from_org: comment.viewer_can_unblock_from_org?(@current_user),
              viewer_did_author: comment.user_id == @current_user&.id, # change this to commit author
              url_fragment: comment.url_fragment,
              viewer_can_read_user_content_edits: comment.viewer_can_read_user_content_edits?(@current_user),
              author: Author.new(
                id: comment.user.id,
                display_login: comment.user.display_login,
                avatar_url: comment.user.primary_avatar_url || User::AvatarList.default_image_url("gravatar-user-420")
              ),
              author_association: comment.author_association_symbol(@current_user), # this might need to be changed to commit author association
              thread_id: "#{comment.path}::#{comment.position}",
            )
          end
        end
      )
    end


    private

    sig { params(comment: CommitComment).returns(Promise[T::Boolean]) }
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

    sig { params(comment: CommitComment).returns(Promise[T::Boolean]) }
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

    sig { params(comment: CommitComment).returns(Promise[T.nilable(UserContentEdit)]) }
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
  end
end
