# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::ThreadComments
  class Payload
    class Author < T::Struct
      const :login, String
      const :avatarUrl, String
    end

    class LastContentEdit < T::Struct
      const :editor, T.nilable(Author)
      const :id, T.nilable(String)
    end

    class Owner < T::Struct
      const :id, String
      const :login, String
      const :url, String
    end

    class ReferenceAuthor < T::Struct
      const :login, String
    end

    class Reference < T::Struct
      const :number, T.nilable(Numeric)
      const :text, T.nilable(String)
      const :author, T.nilable(ReferenceAuthor)
    end

    class Repository < T::Struct
      const :id, String
      const :isPrivate, T::Boolean
      const :name, String
      const :owner, Owner
    end

    class PullRequestComment < T::Struct
      const :author, T.nilable(Author)
      const :authorAssociation, String
      const :body, String
      const :bodyHTML, String
      const :createdAt, String
      const :currentDiffResourcePath, T.nilable(String)
      const :databaseId, T.nilable(Numeric)
      const :id, String
      const :isHidden, T::Boolean
      const :lastUserContentEdit, T.nilable(LastContentEdit)
      const :outdated, T::Boolean
      const :publishedAt, T.nilable(String)
      const :reference, Reference
      const :repository, T.nilable(Repository)
      const :stafftoolsUrl, T.nilable(String)
      const :state, String
      const :subjectType, T.nilable(String)
      const :url, String
      const :viewerCanBlockFromOrg, T::Boolean
      const :viewerCanDelete, T::Boolean
      const :viewerCanMinimize, T::Boolean
      const :viewerCanSeeMinimizeButton, T::Boolean
      const :viewerCanSeeUnminimizeButton, T::Boolean
      const :viewerCanReport, T::Boolean
      const :viewerCanReportToMaintainer, T::Boolean
      const :viewerCanUnblockFromOrg, T::Boolean
      const :viewerCanUpdate, T::Boolean
      const :viewerDidAuthor, T::Boolean
      const :viewerRelationship, String
    end


    sig { params(comments: T::Array[PullRequests::PageData::ThreadComments::Loader::Comment]).returns(T::Array[PullRequestComment]) }
    def self.call(comments)
      new.call(comments)
    end

    sig { params(comments: T::Array[PullRequests::PageData::ThreadComments::Loader::Comment]).returns(T::Array[PullRequestComment]) }
    def call(comments)
      comments_data = comments.map do |loaded_comment_data|
        comment = loaded_comment_data.comment

        last_edit_payload = build_last_edit(loaded_comment_data)

        repository_payload = build_repository(comment)

        author_payload = build_author(loaded_comment_data.author_avatar_url, comment)

        reference_author_payload = build_reference_author(loaded_comment_data)

        PullRequestComment.new(
          author: author_payload,
          authorAssociation: loaded_comment_data.author_association,
          body: comment.body,
          bodyHTML: loaded_comment_data.body_html,
          createdAt: comment.created_at.to_s,
          currentDiffResourcePath: loaded_comment_data.current_diff_resource_path,
          databaseId: comment.id,
          id: comment.global_relay_id,
          isHidden: comment.comment_hidden?,
          lastUserContentEdit: last_edit_payload,
          outdated: loaded_comment_data.outdated,
          publishedAt: loaded_comment_data.published_at,
          reference: Reference.new(
            number: comment.pull_request&.number,
            author: reference_author_payload
          ),
          repository: repository_payload,
          stafftoolsUrl: loaded_comment_data.stafftools_url,
          state: comment.state,
          subjectType: loaded_comment_data.subject_type,
          url: comment.url,
          viewerCanBlockFromOrg: loaded_comment_data.viewer_can_block_from_org,
          viewerCanDelete: loaded_comment_data.viewer_can_delete,
          viewerCanMinimize: loaded_comment_data.viewer_can_minimize,
          viewerCanSeeMinimizeButton: loaded_comment_data.viewer_can_see_minimize_button,
          viewerCanSeeUnminimizeButton: loaded_comment_data.viewer_can_see_unminimize_button,
          viewerCanReport: loaded_comment_data.viewer_can_report,
          viewerCanReportToMaintainer: loaded_comment_data.viewer_can_report_to_maintainer,
          viewerCanUnblockFromOrg: loaded_comment_data.viewer_can_unblock_from_org,
          viewerCanUpdate: loaded_comment_data.viewer_can_update,
          viewerDidAuthor: loaded_comment_data.viewer_did_author,
          viewerRelationship: loaded_comment_data.viewer_relationship
        )
      end
    end

    private

    sig { params(comment: PullRequests::PageData::ThreadComments::Loader::Comment).returns(T.nilable(LastContentEdit)) }
    def build_last_edit(comment)
      last_edit = comment.last_user_content_edit
      if last_edit.present?
        editor = last_edit.editor
        if editor.present?
          editor_payload = Author.new(
            login: editor.display_login,
            avatarUrl: comment.last_editor_avatar_url || ""
          )
        end

        LastContentEdit.new(
          editor: editor_payload,
          id: last_edit.id
        )
      end
    end

    sig { params(comment: PullRequestReviewComment).returns(T.nilable(Repository)) }
    def build_repository(comment)
      repository = comment.repository
      if repository.present?
        owner = repository.owner

        if owner.present?
          Repository.new(
            id: T.must(repository.id).to_s,
            isPrivate: repository.private?,
            name: T.must(repository.name),
            owner: Owner.new(
              id: T.must(owner.id).to_s,
              login: owner.display_login,
              url: owner.async_url.to_s
            )
          )
        end
      end
    end

    sig { params(author_avatar_url: T.nilable(String), comment: PullRequestReviewComment).returns(T.nilable(Author)) }
    def build_author(author_avatar_url, comment)
      author = comment.user
      if author.present?
        Author.new(
          login: author.display_login,
          avatarUrl: author_avatar_url || ""
        )
      end
    end

    sig { params(comment: PullRequests::PageData::ThreadComments::Loader::Comment).returns(T.nilable(ReferenceAuthor)) }
    def build_reference_author(comment)
      if comment.reference_author_login.present?
        ReferenceAuthor.new(
          login: T.must(comment.reference_author_login)
        )
      end
    end
  end
end
