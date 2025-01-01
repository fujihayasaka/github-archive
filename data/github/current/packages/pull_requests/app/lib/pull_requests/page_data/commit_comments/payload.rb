# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::CommitComments
  class Payload
    class Author < T::Struct
      const :id, String
      const :login, String
      const :avatarUrl, String
    end

    class LastContentEdit < T::Struct
      const :editor, T.nilable(Author)
      const :id, T.nilable(String)
    end

    class CommitComment < T::Struct
      const :author, T.nilable(Author)
      const :authorAssociation, Symbol
      const :body, String
      const :createdAt, ActiveSupport::TimeWithZone
      const :htmlBody, String
      const :id, Numeric
      const :isHidden, T::Boolean
      const :lastUserContentEdit, T.nilable(LastContentEdit)
      const :minimizedReason, T.nilable(String)
      const :path, String
      const :position, Numeric
      const :relayId, String
      const :threadId, String
      const :updatedAt, ActiveSupport::TimeWithZone
      const :urlFragment, String
      const :viewerCanBlockFromOrg, T::Boolean
      const :viewerCanDelete, T::Boolean
      const :viewerCanMinimize, T::Boolean
      const :viewerCanReadUserContentEdits, T::Boolean
      const :viewerCanReport, T::Boolean
      const :viewerCanReportToMaintainer, T::Boolean
      const :viewerCanUnblockFromOrg, T::Boolean
      const :viewerCanUpdate, T::Boolean
      const :viewerDidAuthor, T::Boolean
    end


    sig { params(comments: T::Array[PullRequests::PageData::CommitComments::Loader::Comment]).returns(T::Hash[String, T::Hash[Numeric, T::Array[PullRequests::PageData::CommitComments::Payload::CommitComment]]]) }
    def self.call(comments)
      new.call(comments)
    end

    sig { params(comments: T::Array[PullRequests::PageData::CommitComments::Loader::Comment]).returns(T::Hash[String, T::Hash[Numeric, T::Array[PullRequests::PageData::CommitComments::Payload::CommitComment]]]) }
    def call(comments)
      comments_data = comments.map do |loaded_comment_data|

        CommitComment.new(
          id: loaded_comment_data.id,
          relayId: loaded_comment_data.relay_id,
          body: loaded_comment_data.body,
          htmlBody: loaded_comment_data.html_body,
          createdAt: loaded_comment_data.created_at,
          updatedAt: loaded_comment_data.updated_at,
          lastUserContentEdit: build_last_edit(loaded_comment_data),
          path: loaded_comment_data.path,
          position: loaded_comment_data.position,
          isHidden: loaded_comment_data.is_hidden,
          viewerCanMinimize: loaded_comment_data.viewer_can_minimize,
          minimizedReason: loaded_comment_data.minimized_reason,
          viewerCanDelete: loaded_comment_data.viewer_can_delete,
          viewerCanUpdate: loaded_comment_data.viewer_can_update,
          viewerCanReport: loaded_comment_data.viewer_can_report,
          viewerCanReportToMaintainer: loaded_comment_data.viewer_can_report_to_maintainer,
          viewerCanBlockFromOrg: loaded_comment_data.viewer_can_block_from_org,
          viewerCanUnblockFromOrg: loaded_comment_data.viewer_can_unblock_from_org,
          viewerDidAuthor: loaded_comment_data.viewer_did_author,
          urlFragment: loaded_comment_data.url_fragment,
          viewerCanReadUserContentEdits: loaded_comment_data.viewer_can_read_user_content_edits,
          author: build_author(loaded_comment_data.author),
          authorAssociation: loaded_comment_data.author_association,
          threadId: loaded_comment_data.thread_id
        )
      end
      comments_data.group_by { |comment| comment.path }.transform_values do |comments|
        comments.group_by { |comment| comment.position }
      end
    end

    private

    sig { params(comment: PullRequests::PageData::CommitComments::Loader::Comment).returns(T.nilable(LastContentEdit)) }
    def build_last_edit(comment)
      last_edit = comment.last_user_content_edit
      if last_edit.present?
        editor = last_edit.editor
        if editor.present?
          editor_payload = Author.new(
            id: editor.id.to_s,
            login: editor.display_login,
            avatarUrl: editor.primary_avatar_url || ""
          )
        end

        LastContentEdit.new(
          editor: editor_payload,
          id: last_edit.id
        )
      end
    end

    sig { params(author_snake: T.nilable(PullRequests::PageData::CommitComments::Loader::Author)).returns(T.nilable(Author)) }
    def build_author(author_snake)
      if author_snake.present?
        Author.new(
          id: author_snake.id.to_s,
          login: author_snake.display_login,
          avatarUrl: author_snake.avatar_url
        )
      end
    end
  end
end
