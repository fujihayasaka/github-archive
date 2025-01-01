# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::ThreadComments
  class Payload
    class Author < T::Struct
      const :login, String
      const :avatarUrl, String
    end

    # Note(@aliceclv): this is a duplicate of PullRequests::PageData::ThreadPreviews::Payload::DiffLine
    # When previously referring it, it created a circular dependency between ThreadPreviews::Payload && ThreadComments::Payload
    # We might want to extract common types in a helper file if we have more than one duplication
    class DiffLine < T::Struct
      const :html, String
      const :left, T.nilable(Numeric)
      const :right, T.nilable(Numeric)
      const :text, String
      # Note(@aliceclv): Types should be upcased as per definition here: Platform::Enums::DiffLineType
      const :type, String
    end

    class DiffEntry < T::Struct
      const :path, String
      const :diffLines, T::Array[DiffLine]
    end

    class Suggestion < T::Struct
      const :description, String
      const :diffEntries, T::Array[DiffEntry]
    end

    class AutomatedComment < T::Struct
      const :id, String
      const :isDismissed, T::Boolean
      const :message, String
      const :severity, String
      const :source, String
      const :suggestion, T.nilable(Suggestion)
      const :suggestionState, String
      const :title, String
      const :viewerCanDismiss, T::Boolean
      const :viewerCanReopen, T::Boolean
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
      # Note(@aliceclv): we're adding automatedComment alongside the comment as a temporary solution for testing our prototype
      const :automatedComment, T.nilable(AutomatedComment)
      const :body, String
      const :bodyHTML, String
      const :bodyVersion, String
      const :createdAt, String
      const :currentDiffResourcePath, T.nilable(String)
      const :databaseId, T.nilable(Numeric)
      const :id, String
      const :isHidden, T::Boolean
      const :lastUserContentEdit, T.nilable(LastContentEdit)
      const :minimizedReason, T.nilable(String)
      const :publishedAt, T.nilable(String)
      const :reactionGroups, T::Array[PullRequests::PageData::Helpers::Reactable::Payload::ReactionGroup]
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
      const :viewerCanReact, T::Boolean
      const :viewerCanReport, T::Boolean
      const :viewerCanReportToMaintainer, T::Boolean
      const :viewerCanUnblockFromOrg, T::Boolean
      const :viewerCanUpdate, T::Boolean
      const :viewerDidAuthor, T::Boolean
      const :viewerRelationship, String
      const :reviewVariantType, T.nilable(String)
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

        automated_comment = build_automated_comment(loaded_comment_data)

        PullRequestComment.new(
          author: author_payload,
          authorAssociation: loaded_comment_data.author_association,
          automatedComment: automated_comment,
          body: comment.body,
          bodyHTML: loaded_comment_data.body_html,
          bodyVersion: loaded_comment_data.body_version,
          createdAt: comment.created_at.iso8601,
          currentDiffResourcePath: loaded_comment_data.current_diff_resource_path,
          databaseId: comment.id,
          id: comment.global_relay_id,
          isHidden: comment.comment_hidden?,
          lastUserContentEdit: last_edit_payload,
          minimizedReason: comment.minimized_reason,
          publishedAt: loaded_comment_data.published_at,
          reactionGroups: PullRequests::PageData::Helpers::Reactable::Payload.build_reaction_groups(loaded_comment_data.reaction_groups),
          reference: Reference.new(
            number: comment.pull_request&.number,
            author: reference_author_payload
          ),
          repository: repository_payload,
          stafftoolsUrl: loaded_comment_data.stafftools_url,
          state: comment.state,
          subjectType: loaded_comment_data.subject_type,
          url: loaded_comment_data.url,
          viewerCanBlockFromOrg: loaded_comment_data.viewer_can_block_from_org,
          viewerCanDelete: loaded_comment_data.viewer_can_delete,
          viewerCanReact: loaded_comment_data.viewer_can_react,
          viewerCanMinimize: loaded_comment_data.viewer_can_minimize,
          viewerCanSeeMinimizeButton: loaded_comment_data.viewer_can_see_minimize_button,
          viewerCanSeeUnminimizeButton: loaded_comment_data.viewer_can_see_unminimize_button,
          viewerCanReport: loaded_comment_data.viewer_can_report,
          viewerCanReportToMaintainer: loaded_comment_data.viewer_can_report_to_maintainer,
          viewerCanUnblockFromOrg: loaded_comment_data.viewer_can_unblock_from_org,
          viewerCanUpdate: loaded_comment_data.viewer_can_update,
          viewerDidAuthor: loaded_comment_data.viewer_did_author,
          viewerRelationship: loaded_comment_data.viewer_relationship,
          reviewVariantType: loaded_comment_data.review_variant_type&.serialize,
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
            id: repository.id.to_s,
            isPrivate: repository.private?,
            name: repository.name,
            owner: Owner.new(
              id: owner.id.to_s,
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

    sig { params(automated_comment: AutomatedReviewComment).returns(T.nilable(Suggestion)) }
    def build_suggestion(automated_comment)
      suggestion = automated_comment.suggestion
      return unless suggestion && suggestion.description.present?

      diff_entries = suggestion.diff_entries_payload

      Suggestion.new(
        description: suggestion.description,
        diffEntries: diff_entries
      )
    end

    sig { params(comment: PullRequests::PageData::ThreadComments::Loader::Comment).returns(T.nilable(AutomatedComment)) }
    def build_automated_comment(comment)
      automated_comment = comment.automated_comment
      return unless automated_comment

      AutomatedComment.new(
        id: automated_comment.id.to_s,
        isDismissed: automated_comment.dismissed?,
        message: automated_comment.message,
        severity: automated_comment.severity.delete_prefix("severity_"),
        source: automated_comment.source.delete_prefix("source_"),
        suggestion: build_suggestion(automated_comment),
        suggestionState: automated_comment.suggestion_state.delete_prefix("suggestion_state_"),
        title: automated_comment.title,
        viewerCanDismiss: comment.viewer_can_dismiss_automated_comment,
        viewerCanReopen: comment.viewer_can_reopen_automated_comment,
      )
    end
  end
end
